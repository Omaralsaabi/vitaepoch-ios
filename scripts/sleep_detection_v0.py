#!/usr/bin/env python3
"""Deterministic, offline two-night vendor-reference benchmark. No app imports or writes."""
import os
# Keep native math repeatable and local; no dependency installation occurs here.
os.environ['OMP_NUM_THREADS'] = '1'
os.environ['OPENBLAS_NUM_THREADS'] = '1'
os.environ['MKL_NUM_THREADS'] = '1'
import argparse
from bisect import bisect_left, bisect_right
from collections import Counter, defaultdict
import csv
from datetime import datetime, timezone
import hashlib
import json
import math
from pathlib import Path
import platform
import random
import statistics
import subprocess
import tempfile
from zoneinfo import ZoneInfo
import numpy as np
import scipy
import sklearn
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import roc_auc_score, average_precision_score
from sklearn.preprocessing import StandardScaler

ROOT = Path(__file__).resolve().parent.parent
SEED = 20260928
NIGHTS = ['2026-09-27', '2026-09-28']
WINDOWS = [3, 5, 10, 30]
WINDOW_NAMES = ['raw_mean', 'raw_median', 'raw_min', 'raw_max', 'raw_range', 'raw_std',
                'fraction_0x80', 'fraction_non_0x80', 'mean_abs_delta', 'max_abs_delta',
                'byte_transitions', 'longest_0x80_run']
THRESHOLD_FEATURES = ['fraction_non_0x80_5m', 'mean_abs_delta_5m', 'max_abs_delta_5m', 'raw_range_5m']
# Fixed before examining fits; no hyperparameter or feature-subset search.
FEATURE_SETS = {
    'raw_byte_only': ['raw_u8'],
    'code_0x80_only': ['is_0x80', 'distance_from_0x80_code', 'fraction_non_0x80_5m', 'longest_0x80_run_5m'],
    'delta_only': ['abs_delta_from_previous_raw', 'mean_abs_delta_5m', 'max_abs_delta_5m', 'byte_transitions_5m'],
    'rolling': ['raw_mean_5m', 'raw_std_5m', 'raw_range_5m', 'fraction_non_0x80_5m', 'raw_std_30m', 'fraction_non_0x80_30m'],
    'combined_movement': ['raw_u8', 'fraction_non_0x80_5m', 'mean_abs_delta_5m', 'raw_range_5m', 'fraction_non_0x80_30m'],
}
CLOCK = ['minute_of_night', 'clock_sin', 'clock_cos']
ALIGNMENTS = {
    NIGHTS[0]: 'docs/analysis/2026-09-28/comparison-2026-09-27',
    NIGHTS[1]: 'docs/analysis/2026-09-28',
}
STAGES = {'Core': 0, 'REM': 0, 'Deep': 0, 'Awake': 1}

def read(path): return json.loads(Path(path).read_text())
def stamp(value):
    seconds = datetime.fromisoformat(value.replace('Z', '+00:00')).timestamp()
    return int(seconds) if seconds.is_integer() else seconds
def iso(t): return datetime.fromtimestamp(t, timezone.utc).isoformat().replace('+00:00', 'Z')
def dump(path, obj):
    Path(path).write_text(json.dumps(obj, indent=2, sort_keys=True, allow_nan=False) + '\n')
def write_csv(path, rows):
    fields = list(rows[0]) if rows else []
    with Path(path).open('w', newline='') as stream:
        writer = csv.DictWriter(stream, fieldnames=fields, lineterminator='\n')
        writer.writeheader()
        for row in rows:
            writer.writerow({k: json.dumps(v, separators=(',', ':')) if isinstance(v, (dict, list)) else v for k, v in row.items()})
def stats(values):
    a = np.asarray(values, dtype=float)
    if not len(a): return {'count': 0, 'mean': None, 'median': None, 'q1': None, 'q3': None, 'iqr': None, 'min': None, 'max': None}
    q1, q3 = np.quantile(a, [0.25, 0.75], method='linear')
    return {'count': len(a), 'mean': float(a.mean()), 'median': float(np.median(a)), 'q1': float(q1), 'q3': float(q3),
            'iqr': float(q3-q1), 'min': float(a.min()), 'max': float(a.max())}
def support(labels):
    return {'Sleep': sum(y == 0 for y in labels), 'Awake': sum(y == 1 for y in labels), 'total': len(labels)}
def row_support(rows): return support([r['awake_reference'] for r in rows])

def movement_features(t, context):
    current = context.get(t)
    valid = current is not None and current['availability'] == 'observedRawSignal'
    raw = current['rawValue'] if valid else None
    previous = context.get(t-60)
    prev_valid = previous is not None and previous['availability'] == 'observedRawSignal'
    delta = raw-previous['rawValue'] if valid and prev_valid else None
    out = {'movement_valid': int(valid), 'raw_u8': raw, 'is_0x80': int(raw == 128) if valid else None,
           'distance_from_0x80_code': abs(raw-128) if valid else None,
           'delta_from_previous_raw': delta, 'abs_delta_from_previous_raw': abs(delta) if delta is not None else None}
    for size in WINDOWS:
        points = [context.get(t-60*i) for i in range(size-1, -1, -1)]
        count = sum(p is not None and p['availability'] == 'observedRawSignal' for p in points)
        out[f'window_valid_{size}m'] = int(count == size)
        out[f'window_observed_count_{size}m'] = count
        values = None
        if count == size:
            a = [p['rawValue'] for p in points]
            changes = [abs(b-a) for a, b in zip(a, a[1:])]
            longest = run = 0
            for v in a:
                run = run+1 if v == 128 else 0
                longest = max(longest, run)
            fraction = a.count(128)/size
            values = [statistics.mean(a), statistics.median(a), min(a), max(a), max(a)-min(a), statistics.pstdev(a),
                      fraction, 1-fraction, statistics.mean(changes), max(changes), sum(v != 0 for v in changes), longest]
        for i, name in enumerate(WINDOW_NAMES): out[f'{name}_{size}m'] = values[i] if values is not None else None
    return out

def exact_vendor(row, t):
    out = {}
    for name, metric, unit in [('hr', 'heartRate', 'count/min'), ('sdnn', 'sdnn', 'ms')]:
        values = [o for o in row.get('vendorObservations', []) if o['metric'] == metric and stamp(o['timestamp']) == t
                  and o['sourceName'] == 'Da Halo' and o['unit'] == unit]
        out[f'has_{name}'] = int(bool(values))
        out[f'{name}_count'] = len(values)
        # Ambiguous duplicate observations are not silently averaged into a new sample.
        out[name] = values[0]['value'] if len(values) == 1 else None
        out[f'{name}_record_ids'] = [v['recordID'] for v in values]
    return out

def make_row(night, t, context, aligned, start, labeled=True):
    source = aligned.get(t, {})
    point = context.get(t)
    stage = source.get('groundTruthStage') if labeled else None
    local = datetime.fromtimestamp(t, ZoneInfo('Asia/Amman'))
    clock = local.hour*60+local.minute
    row = {'night': night, 'minute': iso(t), 'original_stage': stage, 'binary_reference': ('Awake' if STAGES[stage] else 'Sleep') if stage in STAGES else None,
           'awake_reference': STAGES.get(stage), 'movement_raw_evidence': point['rawValue'] if point else None,
           'movement_availability': point['availability'] if point else 'missing', 'movement_packet_id': point['packetID'] if point else None,
           'movement_selector': point.get('selector') if point else None}
    row.update(movement_features(t, context))
    row.update(exact_vendor(source, t))
    # Explicit leakage control only. These columns are excluded from primary predictors.
    row.update({'minute_of_night': (t-start)/60, 'clock_sin': math.sin(2*math.pi*clock/1440), 'clock_cos': math.cos(2*math.pi*clock/1440)})
    return row

def make_dataset(nights):
    rows = []
    for night, data in sorted(nights.items()):
        context = data['context']; aligned = data['aligned']; start = min(aligned)
        for t, source in sorted(aligned.items()):
            # Existing aligned artifacts remain the label and in-window movement authority.
            point = context.get(t)
            assert (point['rawValue'] if point else None) == source.get('movementRaw')
            assert (point['availability'] if point else None) == source.get('movementAvailability')
            rows.append(make_row(night, t, context, aligned, start))
    return rows

def prepare_sources(output):
    nights = {}; source_paths = []
    # Use the existing Swift decoder for context; no Python protocol decoder or label reconstruction.
    for night in NIGHTS:
        base = ROOT/ALIGNMENTS[night]
        capture = ROOT/f'Tests/VitaEpochCoreTests/Fixtures/physical-{night}/capture.json'
        inputs = [capture, base/'sleep-reference.json', base/'vendor-observations.json', base/'alignment.json']
        with tempfile.TemporaryDirectory(prefix='x6-sleep-v0-') as directory:
            args = ['swift', 'run', '--quiet', 'x6-sleep-analysis', str(capture), str(base/'sleep-reference.json'), directory,
                    '--vendor-observations', str(base/'vendor-observations.json'), '--export-movement-context']
            if night == NIGHTS[1]:
                extra = ROOT/'Tests/VitaEpochCoreTests/Fixtures/physical-2026-09-28-previous-day/capture.json'
                args += ['--movement-evidence', str(extra)]; inputs.append(extra)
            result = subprocess.run(args, cwd=ROOT, capture_output=True, text=True)
            if result.returncode: raise RuntimeError(result.stderr)
            original = read(base/'alignment.json')
            assert read(Path(directory)/'alignment.json') == original, 'Replay differs from source-of-truth alignment'
            context_bytes = (Path(directory)/'movement-context.json').read_bytes()
        context_file = output/f'movement-context-{night}.json'; context_file.write_bytes(context_bytes)
        points = json.loads(context_bytes)
        context = {stamp(p['minute']): p for p in points}
        assert len(context) == len(points), 'Duplicate minute context'
        nights[night] = {'context': context, 'aligned': {stamp(r['minute']): r for r in original['rows']},
                         'reference': read(base/'sleep-reference.json')}
        source_paths += inputs
    provenance = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in source_paths}
    return nights, provenance

def binary_metrics(y, predictions, scores=None):
    assert len(y) == len(predictions)
    tn = sum(a == 0 and b == 0 for a,b in zip(y,predictions)); fp = sum(a == 0 and b == 1 for a,b in zip(y,predictions))
    fn = sum(a == 1 and b == 0 for a,b in zip(y,predictions)); tp = sum(a == 1 and b == 1 for a,b in zip(y,predictions))
    def ratio(a,b): return a/b if b else None
    sleep_recall, awake_recall = ratio(tn,tn+fp), ratio(tp,tp+fn)
    sleep_f1, awake_f1 = ratio(2*tn,2*tn+fn+fp), ratio(2*tp,2*tp+fp+fn)
    both = tn+fp > 0 and tp+fn > 0
    result = {'support': support(y), 'predicted_support': support(predictions), 'positive_class': 'Awake',
        'confusion_matrix': {'rows_true_columns_predicted': ['Sleep','Awake'], 'values': [[tn,fp],[fn,tp]]},
        'accuracy': ratio(tn+tp,len(y)), 'sleep_recall': sleep_recall, 'awake_recall': awake_recall,
        'sleep_precision': ratio(tn,tn+fn), 'awake_precision': ratio(tp,tp+fp), 'specificity': sleep_recall,
        'balanced_accuracy': (sleep_recall+awake_recall)/2 if both else None,
        'f1_awake': awake_f1, 'f1_macro': (sleep_f1+awake_f1)/2 if both and sleep_f1 is not None and awake_f1 is not None else None,
        'auroc': float(roc_auc_score(y,scores)) if both and scores is not None else None,
        'auprc': float(average_precision_score(y,scores)) if both and scores is not None else None}
    result['undefined_reasons'] = {k: ('requires both reference classes' if k in ['balanced_accuracy','f1_macro','auroc','auprc'] and not both
                                    else 'requires scores' if k in ['auroc','auprc'] else 'zero denominator')
                                   for k,v in result.items() if v is None}
    return result

def threshold_predictions(values, fitted):
    return [int(v >= fitted['threshold']) if fitted['operator'] == '>=' else int(v <= fitted['threshold']) for v in values]

def select_threshold(values, labels):
    if len(set(labels)) != 2: return None
    unique = sorted(set(values))
    candidates = [math.nextafter(unique[0], -math.inf)] + unique + [math.nextafter(unique[-1], math.inf)]
    best = None; best_key = None
    for operator in ['>=','<=']:
        for threshold in candidates:
            fitted = {'operator':operator,'threshold':threshold}
            predicted = threshold_predictions(values,fitted)
            # Training-only objective; deterministic ties retain first operator/threshold.
            m = binary_metrics(labels,predicted)
            key = (m['balanced_accuracy'], m['f1_awake'])
            if best_key is None or key > best_key:
                best_key = key; best = dict(fitted, training_balanced_accuracy=key[0], training_f1_awake=key[1])
    return best

def split_nights(rows, train, test):
    assert train != test
    a = [r for r in rows if r['night'] == train]; b = [r for r in rows if r['night'] == test]
    assert {r['night'] for r in a}.isdisjoint({r['night'] for r in b})
    return a,b

def shuffle_labels(labels):
    result = list(labels); random.Random(SEED).shuffle(result); return result

def fit_logistic(train_rows, features, labels):
    x = np.asarray([[r[f] for f in features] for r in train_rows], dtype=float)
    scaler = StandardScaler().fit(x)
    model = LogisticRegression(C=1.0, class_weight='balanced', solver='liblinear', random_state=SEED, max_iter=1000, tol=1e-8)
    model.fit(scaler.transform(x), labels)
    if int(model.n_iter_.max()) >= 1000: raise RuntimeError('Logistic regression did not converge')
    return scaler,model

def evaluate(rows, train, test, features, model_type, cohort='A', shuffled=False, name=None):
    full_train,full_test = split_nights(rows,train,test)
    def in_cohort(r):
        return (cohort == 'A' or r['hr'] is not None) and (cohort != 'C' or r['sdnn'] is not None)
    cohort_train = [r for r in full_train if in_cohort(r)]
    cohort_test = [r for r in full_test if in_cohort(r)]
    valid = lambda r: r['awake_reference'] in [0,1] and all(r[f] is not None for f in features)
    training = [r for r in cohort_train if valid(r)]; testing = [r for r in cohort_test if valid(r)]
    labels = [r['awake_reference'] for r in training]; y = [r['awake_reference'] for r in testing]
    fitted_y = shuffle_labels(labels) if shuffled else labels
    result = {'name':name or model_type, 'model':model_type, 'features':features, 'cohort':cohort,
        'train_night':train, 'test_night':test, 'training_support':support(labels), 'test_support':support(y),
        'training_night_support':row_support(full_train), 'test_night_support':row_support(full_test),
        'cohort_training_support':row_support(cohort_train),'cohort_test_support':row_support(cohort_test),
        'excluded_missing_features_train':row_support([r for r in cohort_train if not valid(r)]),
        'excluded_missing_features_test':row_support([r for r in cohort_test if not valid(r)]),
        'shuffled_training_labels':shuffled,'status':'evaluated',
        'test_row_ids':[r['minute'] for r in testing], 'fit':None, 'metrics':None,
        'matched_always_sleep':binary_metrics(y,[0]*len(y),[0.0]*len(y)), 'limitations':[]}
    if support(labels)['Awake'] < 10: result['limitations'].append('Fewer than 10 training Awake minutes: highly underpowered exploratory fit; no oversampling.')
    if cohort != 'A': result['limitations'].append('Sparse exact-observation cohort; not comparable with all-minute accuracy; inspect matched baseline/cohort ablation.')
    if model_type != 'majority' and len(set(fitted_y)) < 2:
        result.update(status='not_trainable_single_class', metrics=None); return result,[]
    if not testing:
        result.update(status='no_eligible_test_rows', metrics=None); return result,[]
    if model_type == 'majority':
        predictions=[0]*len(y);scores=[0.0]*len(y)
    elif model_type == 'threshold':
        fit=select_threshold([r[features[0]] for r in training],fitted_y)
        result['fit']=fit
        values=[r[features[0]] for r in testing]
        predictions=threshold_predictions(values,fit)
        scores=[v if fit['operator']=='>=' else -v for v in values]
    elif model_type == 'logistic':
        scaler,model=fit_logistic(training,features,fitted_y)
        scores=model.predict_proba(scaler.transform([[r[f] for f in features] for r in testing]))[:,1].tolist()
        predictions=[int(p>=0.5) for p in scores]
        result['fit']={'C':1.0,'solver':'liblinear','class_weight':'balanced','decision_probability':0.5,
            'training_means':scaler.mean_.tolist(),'training_scales':scaler.scale_.tolist(),
            'standardized_coefficients':model.coef_[0].tolist(),'intercept':float(model.intercept_[0]),
            'original_unit_coefficients':(model.coef_[0]/scaler.scale_).tolist(),
            'original_unit_intercept':float(model.intercept_[0]-np.dot(model.coef_[0]/scaler.scale_,scaler.mean_)),
            'iterations':int(model.n_iter_[0])}
    else: raise ValueError(model_type)
    result['metrics']=binary_metrics(y,predictions,scores)
    outputs=[{'experiment':result['name'],'train_night':train,'test_night':test,'minute':r['minute'],
              'vendor_reference':r['binary_reference'],'predicted_awake':p,'awake_score':s,'shuffled_training_labels':int(shuffled)}
             for r,p,s in zip(testing,predictions,scores)]
    return result,outputs

def pair_distribution(x,y):
    if not x or not y: return {'cliffs_delta':None,'probability_x_greater_with_half_ties':None,'common_range':None,'x_fraction_in_common_range':None,'y_fraction_in_common_range':None}
    sy=sorted(y); greater=sum(bisect_left(sy,v) for v in x); less=sum(len(sy)-bisect_right(sy,v) for v in x)
    delta=(greater-less)/(len(x)*len(y)); lo=max(min(x),min(y));hi=min(max(x),max(y))
    return {'cliffs_delta':delta,'probability_x_greater_with_half_ties':(delta+1)/2,'common_range':[lo,hi] if lo<=hi else None,
            'x_fraction_in_common_range':sum(lo<=v<=hi for v in x)/len(x), 'y_fraction_in_common_range':sum(lo<=v<=hi for v in y)/len(y)}

def stage_descriptives(rows):
    features=['raw_u8','is_0x80','distance_from_0x80_code','abs_delta_from_previous_raw']+[f'{name}_{w}m' for w in WINDOWS for name in WINDOW_NAMES]+['hr','sdnn']
    nights={}
    for night in NIGHTS:
        group=[r for r in rows if r['night']==night]; results={}
        for feature in features:
            by={stage:[r[feature] for r in group if r['original_stage']==stage and r[feature] is not None] for stage in STAGES}
            pairs={}
            for name,x,y in [('Core_vs_REM',by['Core'],by['REM']),('Deep_vs_nonDeep',by['Deep'],by['Core']+by['REM']+by['Awake']),('Awake_vs_Sleep',by['Awake'],by['Core']+by['REM']+by['Deep'])]:
                pairs[name]={'first':stats(x),'second':stats(y),**pair_distribution(x,y)}
            results[feature]={'stages':{s:stats(v) for s,v in by.items()},'pairs':pairs}
        nights[night]=results
    return {'interpretation':'Descriptive within-night distributions only, not four-class training or independent-subject inference. Cliff delta = P(first>second)-P(first<second), ties contribute zero. Common-range overlap is not a classifier.', 'nights':nights}

def boundary_outputs(nights):
    windows=[];session=[];events=[]
    for night,data in sorted(nights.items()):
        aligned=data['aligned'];start=min(aligned);end=max(aligned)+60
        intervals=data['reference']['intervals']
        for index,(left,right) in enumerate(zip(intervals,intervals[1:])):
            if stamp(left['end'])!=stamp(right['start']): continue
            a,b=STAGES[left['stage']],STAGES[right['stage']]
            kind='Sleep -> Awake' if a==0 and b==1 else 'Awake -> Sleep' if a==1 and b==0 else 'Sleep stage -> another sleep stage'
            t=stamp(right['start']);event_id=f'{night}:{index:02d}'
            events.append({'night':night,'event_id':event_id,'type':kind,'minute':iso(t),'from_stage':left['stage'],'to_stage':right['stage']})
            for offset in range(-10,11):
                row=make_row(night,t+offset*60,data['context'],aligned,start)
                windows.append({'event_id':event_id,'night':night,'type':kind,'from_stage':left['stage'],'to_stage':right['stage'],
                    'offset_minutes':offset,**{k:row[k] for k in ['minute','original_stage','movement_availability','raw_u8','abs_delta_from_previous_raw',
                        'fraction_non_0x80_5m','raw_range_5m','window_valid_5m','hr','sdnn','has_hr','has_sdnn']}})
        for name,t in [('vendor_session_start',start),('vendor_session_end',end)]:
            for offset in range(-30,31):
                row=make_row(night,t+offset*60,data['context'],aligned,start)
                session.append({'boundary':name,'offset_minutes':offset,**row})
    summary={'events':events,'groups':{},'caveat':'Vendor boundaries, not independently measured transitions. Overlapping event windows are correlated; no lag optimization. Exported individual windows precede summaries.'}
    for night in NIGHTS:
        for kind in ['Sleep -> Awake','Awake -> Sleep','Sleep stage -> another sleep stage']:
            events_count=sum(e['night']==night and e['type']==kind for e in events)
            group={'boundary_count':events_count,'limitation':'Very few independent boundaries; no inferential claim.' if events_count<10 else 'Within-night boundaries remain correlated.','offsets':{}}
            for offset in range(-10,11):
                selected=[r for r in windows if r['night']==night and r['type']==kind and r['offset_minutes']==offset]
                group['offsets'][str(offset)]={f:stats([r[f] for r in selected if r[f] is not None]) for f in ['raw_u8','abs_delta_from_previous_raw','fraction_non_0x80_5m','raw_range_5m','hr','sdnn']}
            summary['groups'][night+' '+kind]=group
    session_summary={}
    for night in NIGHTS:
        for boundary in ['vendor_session_start','vendor_session_end']:
            groups={}
            for period,test in [('before',lambda v:v<0),('at_and_after',lambda v:v>=0)]:
                selected=[r for r in session if r['night']==night and r['boundary']==boundary and test(r['offset_minutes'])]
                groups[period]={'grid_minutes':len(selected),'observed_minutes':sum(r['movement_valid'] for r in selected),
                    'features':{f:stats([r[f] for r in selected if r[f] is not None]) for f in ['raw_u8','abs_delta_from_previous_raw','fraction_non_0x80_5m','raw_range_5m']}}
            session_summary[night+' '+boundary]=groups
    return windows,summary,session,{'groups':session_summary,'caveat':'Outside-session minutes are unlabeled, never assumed Awake. Before/after uses [-30,-1] and [0,+30]; session end is exclusive. Only captured valid bytes produce features.'}

def run_benchmarks(rows):
    folds={};thresholds=[];ablations=[];shuffle=[];clock=[];coefficients=[];predictions=[]
    for train,test in [(NIGHTS[0],NIGHTS[1]),(NIGHTS[1],NIGHTS[0])]:
        runs=[]
        def run(features,model,name,cohort='A',shuffled=False):
            r,p=evaluate(rows,train,test,features,model,cohort,shuffled,name)
            predictions.extend(p)
            if model=='logistic' and r['fit'] is not None: coefficients.append({k:r[k] for k in ['name','train_night','test_night','features','cohort','shuffled_training_labels','fit']})
            return r
        runs.append(run([],'majority','always_sleep_all_labeled'))
        for feature in THRESHOLD_FEATURES:
            r=run([feature],'threshold','threshold_'+feature);runs.append(r);thresholds.append(r)
            shuffle.append(run([feature],'threshold','shuffle_threshold_'+feature,shuffled=True))
        combined=FEATURE_SETS['combined_movement']
        runs.append(run(combined,'logistic','A_movement'))
        for cohort,extra in [('B',['hr']),('C',['hr','sdnn'])]:
            runs.append(run(combined+extra,'logistic',cohort+'_exact_vendor',cohort))
            runs.append(run(combined,'logistic','A_on_'+cohort+'_same_rows',cohort))
        for name,features in FEATURE_SETS.items():
            ablations.append(run(features,'logistic','ablation_'+name))
            # Same complete-case cohort for all feature ablations, avoiding missingness advantage.
            common=[r for r in rows if all(r[f] is not None for f in sorted({f for fs in FEATURE_SETS.values() for f in fs}))]
            result,p=evaluate(common,train,test,features,'logistic',name='ablation_common_'+name)
            predictions.extend(p);ablations.append(result)
            if result['fit'] is not None:
                coefficients.append({k:result[k] for k in ['name','train_night','test_night','features','cohort','shuffled_training_labels','fit']})
        shuffle.append(run(combined,'logistic','shuffle_A_movement',shuffled=True))
        clock.append(run(CLOCK,'logistic','time_only_oracle_schedule'))
        clock.append(run(combined+CLOCK,'logistic','movement_plus_oracle_schedule'))
        folds[train+'-to-'+test]={'train_night':train,'test_night':test,'runs':runs,'evaluation':'Leave-one-night-out; no row split. All preprocessing and thresholds fit on training rows only. No prediction smoothing.'}
    return folds,thresholds,ablations,shuffle,clock,coefficients,predictions

def manifest(provenance):
    return {'task':'Sleep vs Awake agreement with vendor reference; offline research only','seed':SEED,
        'label_mapping':{'Core':'Sleep','REM':'Sleep','Deep':'Sleep','Awake':'Awake'},'positive_class':'Awake',
        'input_sha256':provenance,'versions':{'python':platform.python_version(),'numpy':np.__version__,'scipy':scipy.__version__,'scikit_learn':sklearn.__version__},
        'feature_definitions':{
            'raw_u8':'Unmodified byte, no physiological units. Null unless observedRawSignal.',
            'is_0x80':'1 exactly for byte 128; null when missing.',
            'distance_from_0x80_code':'abs(raw_u8-128); encoding-relative distance, not movement magnitude.',
            'delta_from_previous_raw':'Current minus immediately previous minute; null if either is missing/zero-uninterpreted/future.',
            'abs_delta_from_previous_raw':'Absolute signed adjacent-byte change; no bridging gaps.',
            'rolling':'Trailing, causal, includes current minute; require all exact N consecutive minute timestamps valid. Population standard deviation (ddof=0). Adjacent changes use N-1 pairs. Longest 0x80 run counted only inside window.',
            'windows_minutes':WINDOWS,'window_statistics':WINDOW_NAMES,
            'missingness':'Raw evidence retained separately. Missing/zeroUninterpreted/future invalidates features; no filling, partial-window averages or imputation. Validity flags and observed counts are metadata, not predictors.',
            'hr_sdnn':'Exactly one Da Halo export observation starting at this exact minute. No floor/round, interval expansion, carry, interpolation or averaging duplicate records. Explicit has_hr/has_sdnn and source record IDs.',
            'context':'Captured unlabeled minutes before session allowed for causal rolling features, from same nightly input archive only. Context derived by existing Swift decoder, not other-night joins.',
            'clock':'Separate leakage-control predictors only. minute_of_night uses vendor session start (oracle schedule information); sin/cos use local wall clock. Not wearable evidence.'},
        'predeclared_movement_feature_sets':FEATURE_SETS,'threshold_features':THRESHOLD_FEATURES,
        'threshold_selection':'Training-only maximum balanced accuracy; tie-break training Awake F1, then first candidate in >=/<= order and ascending observed thresholds plus two extreme bounds. No held-out selection.',
        'model':'StandardScaler fitted on training rows; LogisticRegression C=1, class_weight=balanced, solver=liblinear, tol=1e-8, max_iter=1000, fixed seed, probability cutoff 0.5. No hyperparameter search, oversampling or smoothing.',
        'metrics':'Awake is positive; specificity equals Sleep recall. AUROC and AUPRC only with both classes and scores; AUPRC is non-interpolated average precision. Undefined values are null with reasons. No pooled/mean-fold headline metric.',
        'ablations':'Both native complete-case and common-complete-case cohorts; latter fixes row support across feature families.',
        'negative_control':'Labels shuffled within each eligible training fold with fixed Python Random seed. Test labels unchanged. Not a permutation p-value.',
        'evidence_terms':['captured fact','physically validated transport','vendor reference','derived feature','exploratory association','cross-night evidence','unsupported / unknown'],
        'non_goals':['No production samples','No four-class classifier','No oxygen feature','No sequence model','No HealthKit runtime dependency']}

def format_metric(v): return 'undefined' if v is None else f'{v:.4f}'
def write_summary(output, rows, folds, ablations, shuffle):
    text='# Sleep Detection V0 — offline vendor-reference benchmark\n\n'
    text+='Two nights from one X6/user. Labels are vendor reference, not clinical ground truth. No production sleep result is created.\n\n'
    text+='| Night | Labeled Sleep / Awake | Valid movement Sleep / Awake | Valid trailing 30m Sleep / Awake | Exact HR Sleep / Awake | Exact SDNN Sleep / Awake |\n|---|---|---|---|---|---|\n'
    for night in NIGHTS:
        r=[x for x in rows if x['night']==night]
        def counts(a):s=row_support(a);return f"{s['Sleep']} / {s['Awake']}"
        text+=f"| {night} | {counts(r)} | {counts([x for x in r if x['movement_valid']])} | {counts([x for x in r if x['window_valid_30m']])} | {counts([x for x in r if x['has_hr']])} | {counts([x for x in r if x['has_sdnn']])} |\n"
    text+='\n## Held-out results\n\nRaw confusion matrices, all requested metrics, eligibility exclusions and undefined reasons are in the fold/metrics JSON files. Always-Sleep is also evaluated on every model’s exact eligible test cohort. Thresholds/scalers use training rows only.\n\n'
    text+='| Train → test | Baseline | Test Sleep / Awake | Accuracy | Awake recall | Balanced accuracy | Awake F1 | AUROC | AUPRC |\n|---|---|---|---|---|---|---|---|---|\n'
    for fold in folds.values():
        for r in fold['runs']:
            m=r['metrics'];s=r['test_support']; vals=[format_metric(m[k]) if m else r['status'] for k in ['accuracy','awake_recall','balanced_accuracy','f1_awake','auroc','auprc']]
            text+=f"| {r['train_night'][-2:]} → {r['test_night'][-2:]} | {r['name']} | {s['Sleep']} / {s['Awake']} | "+' | '.join(vals)+' |\n'
    text+='\n## Ablations and shuffle controls\n\nNo winner is selected using held-out outcomes. Same-cohort ablations are provided alongside native coverage to expose complete-case selection effects.\n\n| Train → test | Experiment | Test Sleep / Awake | Balanced accuracy | Awake F1 |\n|---|---|---|---|---|\n'
    for r in ablations+shuffle:
        m=r['metrics'];s=r['test_support']
        text+=f"| {r['train_night'][-2:]} → {r['test_night'][-2:]} | {r['name']} | {s['Sleep']} / {s['Awake']} | {format_metric(m['balanced_accuracy']) if m else r['status']} | {format_metric(m['f1_awake']) if m else r['status']} |\n"
    text+='\nThe 28 Sep night contains only three contiguous Awake minutes. HR/SDNN have no Awake observations on that night, preventing meaningful two-direction multimodal evaluation. Class-weighted fits do not add independent Awake evidence. Shuffling is a deterministic sanity check, not a p-value. Clock controls use oracle session timing and must not be interpreted as wearable signal. No four-class stage model or prediction smoothing was run.\n\nSee `docs/SLEEP_DETECTION_V0_2026-09-28.md` for the evidence-based decision gate and next-capture protocol.\n'
    (output/'summary.md').write_text(text)

def main(output):
    output.mkdir(parents=True,exist_ok=True)
    nights,provenance=prepare_sources(output)
    rows=make_dataset(nights)
    assert len(rows)==1097 and row_support(rows)=={'Sleep':1031,'Awake':66,'total':1097}
    write_csv(output/'dataset.csv',rows)
    dump(output/'feature-manifest.json',manifest(provenance))
    folds,thresholds,ablations,shuffle,clock,coefficients,predictions=run_benchmarks(rows)
    dump(output/'fold-27-to-28.json',folds[NIGHTS[0]+'-to-'+NIGHTS[1]])
    dump(output/'fold-28-to-27.json',folds[NIGHTS[1]+'-to-'+NIGHTS[0]])
    dump(output/'metrics.json',{'folds':folds,'fold_aggregation':'None; per-fold values/support and undefined metrics shown explicitly.'})
    dump(output/'single-feature-thresholds.json',thresholds)
    dump(output/'ablation.json',ablations);dump(output/'label-shuffle.json',shuffle)
    dump(output/'time-leakage-check.json',{'caveat':'Separate oracle schedule control; not wearable-signal evidence. No clock variables in primary predictors.','runs':clock})
    dump(output/'model-coefficients.json',coefficients)
    dump(output/'stage-descriptives.json',stage_descriptives(rows))
    windows,summary,session,session_summary=boundary_outputs(nights)
    write_csv(output/'transition-windows.csv',windows);dump(output/'transition-summary.json',summary)
    write_csv(output/'session-boundary-windows.csv',session);dump(output/'session-boundary-summary.json',session_summary)
    write_csv(output/'predictions.csv',predictions)
    write_summary(output,rows,folds,ablations,shuffle)
    print(f'Wrote {len(rows)} labeled rows, {len(windows)} boundary-window rows and two night-held-out folds to {output}')

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,default=ROOT/'docs/analysis/sleep-detection-v0')
    main(parser.parse_args().output)

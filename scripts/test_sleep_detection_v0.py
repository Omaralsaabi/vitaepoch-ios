import copy
import json
import math
from pathlib import Path
import tempfile
import unittest
import sleep_detection_v0 as v

class ResearchTests(unittest.TestCase):
    def context(self, values, start=0):
        return {start+i*60:{'minute':v.iso(start+i*60),'rawValue':value,'availability':'observedRawSignal','packetID':'fixture','selector':'0000'} for i,value in enumerate(values)}
    def row(self, night, value, label, minute):
        return {'night':night,'raw_u8':value,'awake_reference':label,'binary_reference':'Awake' if label else 'Sleep',
                'minute':v.iso(minute),'hr':None,'sdnn':None}
    def test_window_exact_population_statistics_and_run_length(self):
        f=v.movement_features(4*60,self.context([128,128,130,126,128]))
        self.assertEqual(f['raw_mean_5m'],128)
        self.assertEqual(f['raw_median_5m'],128)
        self.assertEqual(f['raw_range_5m'],4)
        self.assertAlmostEqual(f['raw_std_5m'],math.sqrt(8/5))
        self.assertAlmostEqual(f['fraction_0x80_5m'],3/5)
        self.assertEqual(f['mean_abs_delta_5m'],2)
        self.assertEqual(f['max_abs_delta_5m'],4)
        self.assertEqual(f['byte_transitions_5m'],3)
        self.assertEqual(f['longest_0x80_run_5m'],2)
        self.assertEqual(f['delta_from_previous_raw'],2)
        self.assertEqual(f['window_valid_10m'],0)
        self.assertIsNone(f['raw_mean_10m'])
    def test_no_imputation_or_gap_bridging(self):
        c=self.context([128,128,0,130,128]);c[120]['availability']='zeroUninterpreted'
        f=v.movement_features(180,c)
        self.assertIsNone(f['delta_from_previous_raw'])
        self.assertIsNone(f['raw_mean_3m'])
        self.assertEqual(f['window_observed_count_3m'],2)
        self.assertIsNone(v.movement_features(120,c)['raw_u8'])
        c[240]['availability']='future'
        self.assertIsNone(v.movement_features(240,c)['raw_u8'])
        del c[60]
        self.assertIsNone(v.movement_features(60,c)['raw_u8'])
    def test_features_causal_and_night_contexts_separate(self):
        c=self.context([128]*30);before=v.movement_features(29*60,c)
        c[30*60]={'rawValue':255,'availability':'observedRawSignal'}
        self.assertEqual(before,v.movement_features(29*60,c))
        other=self.context([200]*30)
        self.assertNotEqual(before['raw_mean_30m'],v.movement_features(29*60,other)['raw_mean_30m'])
        self.assertEqual(before['raw_mean_30m'],128)
    def test_exact_vendor_start_no_interval_expansion_rounding_or_duplicate_average(self):
        obs={'timestamp':v.iso(0),'end':v.iso(299),'metric':'heartRate','sourceName':'Da Halo','unit':'count/min','value':65,'recordID':'r'}
        row={'vendorObservations':[obs]}
        self.assertEqual(v.exact_vendor(row,0)['hr'],65)
        self.assertEqual(v.exact_vendor(row,60)['has_hr'],0)
        row['vendorObservations'][0]['timestamp']=v.iso(30)
        self.assertEqual(v.exact_vendor(row,0)['has_hr'],0)
        row['vendorObservations'][0]['timestamp']=v.iso(0.5)
        self.assertEqual(v.exact_vendor(row,0)['has_hr'],0)
        obs['timestamp']=v.iso(0)
        duplicate={'vendorObservations':[obs,dict(obs,recordID='r2',value=70)]}
        self.assertEqual(v.exact_vendor(duplicate,0)['has_hr'],1)
        self.assertIsNone(v.exact_vendor(duplicate,0)['hr'])
        sdnn=dict(obs,metric='sdnn',unit='ms',value=12)
        self.assertEqual(v.exact_vendor({'vendorObservations':[sdnn]},0)['sdnn'],12)
    def test_whole_nights_not_random_row_split(self):
        rows=[self.row('a',i,i%2,i*60) for i in range(8)]+[self.row('b',i,i%2,1000+i*60) for i in range(8)]
        a,b=v.split_nights(rows,'a','b')
        self.assertEqual(len(a),8);self.assertEqual(len(b),8)
        self.assertEqual({r['night'] for r in a},{'a'})
        with self.assertRaises(AssertionError):v.split_nights(rows,'a','a')
    def test_training_only_threshold_and_unchanged_heldout_application(self):
        fit=v.select_threshold([0,1,10,11],[0,0,1,1])
        self.assertEqual(fit['operator'],'>=');self.assertEqual(fit['threshold'],10)
        self.assertEqual(v.threshold_predictions([1,5,10,30],fit),[0,0,1,1])
        rows=[self.row('a',x,y,i*60) for i,(x,y) in enumerate(zip([0,1,10,11],[0,0,1,1]))]
        rows+=[self.row('b',x,y,1000+i*60) for i,(x,y) in enumerate(zip([2,8,15,20],[0,1,0,1]))]
        first,_=v.evaluate(rows,'a','b',['raw_u8'],'threshold')
        changed=copy.deepcopy(rows)
        for r in changed:
            if r['night']=='b':r['raw_u8']*=1000;r['awake_reference']=1-r['awake_reference']
        second,_=v.evaluate(changed,'a','b',['raw_u8'],'threshold')
        self.assertEqual(first['fit'],second['fit'])
    def test_logistic_scaling_training_only_and_fixed_predictions(self):
        rows=[self.row('a',x,y,i*60) for i,(x,y) in enumerate(zip([0,1,10,11],[0,0,1,1]))]
        rows+=[self.row('b',2,0,1000),self.row('b',20,1,1060)]
        a,pa=v.evaluate(rows,'a','b',['raw_u8'],'logistic')
        modified=copy.deepcopy(rows);modified[-1]['raw_u8']=10000
        b,_=v.evaluate(modified,'a','b',['raw_u8'],'logistic')
        self.assertEqual(a['fit'],b['fit'])
        self.assertEqual(a['fit']['training_means'],[5.5])
        c,pc=v.evaluate(rows,'a','b',['raw_u8'],'logistic')
        self.assertEqual(a,c);self.assertEqual(pa,pc)
    def test_class_support_and_undefined_metrics(self):
        m=v.binary_metrics([0,0,1],[0,0,0],[0,0,0])
        self.assertEqual(m['confusion_matrix']['values'],[[2,0],[1,0]])
        self.assertEqual(m['awake_recall'],0);self.assertIsNone(m['awake_precision'])
        self.assertEqual(m['specificity'],1);self.assertEqual(m['balanced_accuracy'],0.5)
        self.assertAlmostEqual(m['auprc'],1/3)
        one=v.binary_metrics([0,0],[0,0],[0,0])
        for k in ['awake_recall','awake_precision','auroc','auprc','balanced_accuracy','f1_macro','f1_awake']:self.assertIsNone(one[k])
        empty=v.binary_metrics([],[],[])
        self.assertEqual(empty['support']['total'],0);self.assertIsNone(empty['accuracy'])
    def test_missing_row_accounting_and_single_class_training(self):
        rows=[self.row('a',None,1,0),self.row('a',128,0,60),self.row('b',128,1,120)]
        result,_=v.evaluate(rows,'a','b',['raw_u8'],'logistic')
        self.assertEqual(result['status'],'not_trainable_single_class')
        self.assertEqual(result['excluded_missing_features_train']['Awake'],1)
        self.assertEqual(result['training_support']['Sleep'],1)
        self.assertEqual(result['test_support']['Awake'],1)
    def test_label_shuffle_deterministic_preserves_support(self):
        labels=[0]*30+[1]*5
        shuffled=v.shuffle_labels(labels)
        self.assertEqual(shuffled,v.shuffle_labels(labels))
        self.assertEqual(v.support(shuffled),v.support(labels))
        self.assertNotEqual(shuffled,labels)
        self.assertEqual(labels,[0]*30+[1]*5)
    def test_effect_size_and_descriptive_quantiles(self):
        self.assertEqual(v.pair_distribution([2,3],[0,1])['cliffs_delta'],1)
        self.assertEqual(v.pair_distribution([0,1],[2,3])['cliffs_delta'],-1)
        self.assertEqual(v.pair_distribution([128],[128])['cliffs_delta'],0)
        self.assertEqual(v.pair_distribution([128],[128])['probability_x_greater_with_half_ties'],0.5)
        self.assertIsNone(v.pair_distribution([],[1])['cliffs_delta'])
        self.assertEqual(v.stats([0,1,2,3])['iqr'],1.5)
    def test_outside_session_not_labeled_awake_and_clock_not_primary(self):
        c=self.context([128]*3)
        aligned={60:{'groundTruthStage':'Core','vendorObservations':[]}}
        row=v.make_row('a',0,c,aligned,60)
        self.assertIsNone(row['awake_reference']);self.assertIsNone(row['original_stage'])
        self.assertFalse(set(v.CLOCK)&{f for group in v.FEATURE_SETS.values() for f in group})
        self.assertNotIn('has_hr',v.FEATURE_SETS['combined_movement'])
    def test_deterministic_serialization_and_no_nonfinite_values(self):
        with tempfile.TemporaryDirectory() as d:
            a=Path(d)/'a.json';b=Path(d)/'b.json'
            obj={'undefined':None,'metrics':v.binary_metrics([0,1],[0,1],[0.1,0.9])}
            v.dump(a,obj);v.dump(b,obj);self.assertEqual(a.read_bytes(),b.read_bytes())
            with self.assertRaises(ValueError):v.dump(a,{'bad':float('nan')})
    def test_production_target_does_not_link_research(self):
        project=(v.ROOT/'VitaEpoch.xcodeproj/project.pbxproj').read_text()
        self.assertNotIn('X6Research',project)
        self.assertNotIn('sleep_detection_v0',project)
        domain=(v.ROOT/'Sources/VitaEpochCore/Domain.swift').read_text()
        self.assertNotIn('case sleep',domain)

if __name__=='__main__':unittest.main()

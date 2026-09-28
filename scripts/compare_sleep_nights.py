#!/usr/bin/env python3
"""Compare the 27/28 Sep outputs of x6-sleep-analysis; no fitting or stage prediction."""
import argparse
import json
from pathlib import Path

def load(path): return json.loads(path.read_text())
def number(x): return '—' if x is None else f'{x:.3f}'
def compare(first, second, output):
    nights = []
    for directory in [first, second]:
        stages = load(directory/'statistics.json')
        transition = load(directory/'transitions.json')
        rows = load(directory/'alignment.json')['rows']
        for stage in stages:
            n = stage['movementRaw']['count']
            stage['raw80FractionObserved'] = stage['raw80Minutes']/n if n else None
        nights.append({'source':load(directory/'alignment.json')['source'], 'stages':stages, 'transitions':transition,
            'windowMinutes':len(rows), 'missingMovementMinutes':sum(s['missingMovementMinutes'] for s in stages)})
    # Narrative is specific to this two-night evidence pass, not arbitrary future nights.
    assert '2026-09-27' in nights[0]['source'] and '2026-09-28' in nights[1]['source']
    assert [n['windowMinutes'] for n in nights] == [552, 545]
    output.mkdir(parents=True,exist_ok=True)
    (output/'cross-night-comparison.json').write_text(json.dumps({'nights':nights, 'conclusion':'insufficient evidence for production sleep staging'},indent=2,sort_keys=True)+'\n')
    text = '# Cross-night comparison: 27 vs 28 Sep 2026\n\n'
    text += 'Same X6 and vendor labels, two different nights; correlated minute observations are not independent subjects. Raw amplitude has unknown units. Missing/zero/future positions are excluded, and no values are imputed. Vendor HR/SDNN statistics below use only Da Halo export observations at their recorded starts, separately from packet-decoded signals.\n\n'
    text += '| Night | Stage | Labeled / observed / missing / zero | Raw mean / median | Raw 0x80 fraction | Vendor HR n / mean / median | Vendor SDNN n / mean / median |\n|---|---|---|---|---|---|---|\n'
    for date, night in zip(['27 Sep','28 Sep'],nights):
        for s in night['stages']:
            hr, sdnn = s.get('vendorHeartRate',{}), s.get('vendorSDNN',{})
            text += f"| {date} | {s['stage']} | {s['labeledMinutes']} / {s['movementRaw']['count']} / {s['missingMovementMinutes']} / {s['zeroUninterpretedMinutes']} | {number(s['movementRaw'].get('mean'))} / {number(s['movementRaw'].get('median'))} | {number(s['raw80FractionObserved'])} | {hr.get('count',0)} / {number(hr.get('mean'))} / {number(hr.get('median'))} | {sdnn.get('count',0)} / {number(sdnn.get('mean'))} / {number(sdnn.get('median'))} |\n"
    text += '\n## Questions tested descriptively\n\n'
    for label,night in zip(['27 Sep','28 Sep'],nights):
        by={s['stage']:s for s in night['stages']}
        core,rem,deep=[by[s] for s in ['Core','REM','Deep']]
        text += f"- {label}: Core minus REM raw mean = {number(core['movementRaw']['mean']-rem['movementRaw']['mean'])}; Deep minus Core raw mean = {number(deep['movementRaw']['mean']-core['movementRaw']['mean'])}. "
        text += f"Core minus REM vendor SDNN mean = {number(core['vendorSDNN']['mean']-rem['vendorSDNN']['mean'])} ms; Core minus REM vendor HR mean = {number(core['vendorHeartRate']['mean']-rem['vendorHeartRate']['mean'])} bpm.\n"
    text += '\n- **Core vs REM:** Nearly identical movement means, identical medians (128), and heavily overlapping ranges on both nights. Their tiny mean ordering reverses. Movement alone provides no useful demonstrated separation here.\n'
    text += '- **Deep:** Higher raw mean than Core/REM on 27 Sep, lower on 28 Sep. The direction reverses. The first night has only 11 labeled Deep minutes.\n'
    text += '- **Awake:** First-night raw values overlap sleep; 19 zero/uninterpreted Awake minutes are excluded, and its median is also 128. All three second-night Awake minutes are in the missing 23:30–23:59 window. Awake separation cannot be validated across nights.\n'
    text += '- **SDNN:** Core/REM vendor means are equal on the first night and only 0.083 ms apart on the second. Ranges overlap (10–14 ms). Deep has no first-night observations and only two second-night observations; Awake has none on the second. No meaningful stable stage separation is established. Packet SDNN is sparser still (10 first-night in-window points, no second-night raw 0210 payload supplied).\n'
    text += '- **HR:** Core vendor mean exceeds REM on both nights (1.50 and 5.75 bpm), but ranges overlap substantially. Second-night Deep has two lower HR observations; first-night Deep has none. This is a candidate association to revisit with more captures, not validated stage discrimination. No raw periodic-HR payload was supplied for the second-night alignment.\n'
    text += '- **0x80:** Core/REM fractions stay near 0.82 on both nights. Deep changes from 0.636 to 0.896, reversing its ordering relative to Core/REM. Awake has no second-night coverage. Thus there is no consistent stage-specific byte code. Denominators are observed nonzero positions, not all labeled minutes.\n'
    text += '- **Oxygen:** Neither overnight export contains Da Halo oxygen observations; neither alignment has a 0211 candidate series. The displayed vendor 98% is not converted into minute data.\n'
    text += '\n## Stage transitions and movement changes\n\nExact adjacent-minute absolute raw-byte differences at label boundaries are compared with within-stage pairs. Both positions must be observed; there is no tuned spike threshold, lag search, or classifier.\n\n| Night | Observed / labeled boundaries | Boundary absolute change mean / median | Within-stage mean / median |\n|---|---|---|---|\n'
    for label,night in zip(['27 Sep','28 Sep'],nights):
        t=night['transitions'];b=t['transitionAbsoluteChange'];o=t['nontransitionAbsoluteChange']
        text+=f"| {label} | {t['observedTransitions']} / {t['labeledTransitions']} | {number(b.get('mean'))} / {number(b.get('median'))} | {number(o.get('mean'))} / {number(o.get('median'))} |\n"
    text += '\nThe boundary mean is higher than the within-stage mean on 27 Sep, but lower on 28 Sep; all four medians are zero. The first-night maximum boundary change is 138 raw units and influences its mean. This direction reversal does not support a stable boundary-spike association. This limited boundary check cannot establish causal timing or a general spike-to-stage relationship.\n\n**Conclusion: insufficient evidence for production sleep staging.** No model, threshold classifier, HMM, or sleep score was created.\n'
    (output/'cross-night-comparison.md').write_text(text)

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('first',type=Path);p.add_argument('second',type=Path);p.add_argument('output',type=Path)
    a=p.parse_args();compare(a.first,a.second,a.output)

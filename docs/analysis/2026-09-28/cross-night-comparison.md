# Cross-night comparison: 27 vs 28 Sep 2026

Same X6 and vendor labels, two different nights; correlated minute observations are not independent subjects. Raw amplitude has unknown units. Missing/zero/future positions are excluded, and no values are imputed. Vendor HR/SDNN statistics below use only Da Halo export observations at their recorded starts, separately from packet-decoded signals.

| Night | Stage | Labeled / observed / missing / zero | Raw mean / median | Raw 0x80 fraction | Vendor HR n / mean / median | Vendor SDNN n / mean / median |
|---|---|---|---|---|---|---|
| 27 Sep | Core | 260 / 260 / 0 / 0 | 129.573 / 128.000 | 0.815 | 10 / 70.300 / 71.500 | 10 / 11.200 / 11.000 |
| 27 Sep | REM | 218 / 218 / 0 / 0 | 129.560 / 128.000 | 0.826 | 5 / 68.800 / 66.000 | 5 / 11.200 / 11.000 |
| 27 Sep | Deep | 11 / 11 / 0 / 0 | 134.364 / 128.000 | 0.636 | 0 / — / — | 0 / — / — |
| 27 Sep | Awake | 63 / 44 / 0 / 19 | 128.068 / 128.000 | 0.659 | 3 / 69.667 / 71.000 | 3 / 12.333 / 13.000 |
| 28 Sep | Core | 273 / 273 / 0 / 0 | 129.590 / 128.000 | 0.828 | 4 / 69.750 / 67.000 | 4 / 12.000 / 12.000 |
| 28 Sep | REM | 221 / 221 / 0 / 0 | 129.697 / 128.000 | 0.833 | 12 / 64.000 / 63.000 | 12 / 12.083 / 12.000 |
| 28 Sep | Deep | 48 / 48 / 0 / 0 | 129.208 / 128.000 | 0.896 | 2 / 59.000 / 59.000 | 2 / 12.500 / 12.500 |
| 28 Sep | Awake | 3 / 3 / 0 / 0 | 128.000 / 128.000 | 1.000 | 0 / — / — | 0 / — / — |

## Questions tested descriptively

- 27 Sep: Core minus REM raw mean = 0.013; Deep minus Core raw mean = 4.791. Core minus REM vendor SDNN mean = 0.000 ms; Core minus REM vendor HR mean = 1.500 bpm.
- 28 Sep: Core minus REM raw mean = -0.107; Deep minus Core raw mean = -0.381. Core minus REM vendor SDNN mean = -0.083 ms; Core minus REM vendor HR mean = 5.750 bpm.

- **Core vs REM:** Nearly identical movement means, identical medians (128), and heavily overlapping ranges on both nights. Their tiny mean ordering reverses. Movement alone provides no useful demonstrated separation here.
- **Deep:** Higher raw mean than Core/REM on 27 Sep, lower on 28 Sep. The direction reverses. The first night has only 11 labeled Deep minutes.
- **Awake:** First-night raw values overlap sleep; 19 zero/uninterpreted Awake minutes are excluded, and its median is also 128. Second-night coverage is now 3/3 minutes; raw min/max/mean/median are 128.000/128.000/128.000/128.000. The coverage gap is resolved descriptively, but three Awake minutes cannot validate separation; they overlap the common sleep value.
- **SDNN:** Core/REM vendor means are equal on the first night and only 0.083 ms apart on the second. Ranges overlap (10–14 ms). Deep has no first-night observations and only two second-night observations; Awake has none on the second. No meaningful stable stage separation is established. Packet SDNN is sparser still (10 first-night in-window points, no second-night raw 0210 payload supplied).
- **HR:** Core vendor mean exceeds REM on both nights (1.50 and 5.75 bpm), but ranges overlap substantially. Second-night Deep has two lower HR observations; first-night Deep has none. This is a candidate association to revisit with more captures, not validated stage discrimination. No raw periodic-HR payload was supplied for the second-night alignment.
- **0x80:** Core/REM fractions stay near 0.82 on both nights. Deep changes from 0.636 to 0.896, reversing its ordering relative to Core/REM. Awake coverage/frequency is reported separately below. Thus there is no consistent stage-specific byte code. Denominators are observed nonzero positions, not all labeled minutes.
  Second-night Awake has 3 raw 0x80 minutes among 3 observed minutes, fraction 1.000; this small sample is not a stage rule.
- **Oxygen:** Neither overnight export contains Da Halo oxygen observations; neither alignment has a 0211 candidate series. The displayed vendor 98% is not converted into minute data.

## Stage transitions and movement changes

Exact adjacent-minute absolute raw-byte differences at label boundaries are compared with within-stage pairs. Both positions must be observed; there is no tuned spike threshold, lag search, or classifier.

| Night | Observed / labeled boundaries | Boundary absolute change mean / median | Within-stage mean / median |
|---|---|---|---|
| 27 Sep | 45 / 46 | 6.089 / 0.000 | 2.740 / 0.000 |
| 28 Sep | 45 / 45 | 2.444 / 0.000 | 2.854 / 0.000 |

The boundary mean is higher than the within-stage mean on 27 Sep, but lower on 28 Sep; all four medians are zero. The first-night maximum boundary change is 138 raw units and influences its mean. This direction reversal does not support a stable boundary-spike association. This limited boundary check cannot establish causal timing or a general spike-to-stage relationship.

**Conclusion: insufficient evidence for production sleep staging.** No model, threshold classifier, HMM, or sleep score was created.

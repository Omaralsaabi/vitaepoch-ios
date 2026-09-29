# Sleep Detection V0 — 28 September 2026

Movement-only Sleep/Awake agreement does **not yet generalize reliably in both directions**. Favorable ranking on three contiguous Awake minutes in one held-out night is offset by failure in the reverse direction and negative controls that sometimes outperform the original labels. The appropriate next step is more representative capture, not a production or sequence model.

## Evidence used

- Historical context: [27 Sep evidence](X6_PHYSICAL_EVIDENCE_2026-09-27.md), [28 Sep revalidation](X6_PHYSICAL_REVALIDATION_2026-09-28.md), [previous-day movement](X6_PREVIOUS_DAY_MOVEMENT_2026-09-28.md), and the existing [summary](analysis/2026-09-28/summary.md) and [comparison](analysis/2026-09-28/cross-night-comparison.md). These remain unchanged.
- **Captured fact:** existing packet fixtures, raw bytes, timestamps, selectors, and availability flags. The existing Swift decoder replays the two current-day captures plus the second night's separate previous-day capture. Regenerated alignments must equal the existing source-of-truth artifacts before analysis proceeds.
- **Physically validated transport:** the previously documented X6 history/page observations; this pass adds no radio validation or BLE command.
- **Vendor reference:** existing Da Halo sleep/HR/SDNN records extracted from Apple Health exports, not clinical ground truth. Labels come directly from existing alignment JSON, never manually reconstructed.
- **Derived feature:** deterministic byte statistics, without physiological interpretation of amplitude. **Exploratory association** and **cross-night evidence** are reported below. Clinical validity and production readiness remain **unsupported / unknown**.

Input SHA-256 hashes and local dependency versions are recorded in [feature-manifest.json](analysis/sleep-detection-v0/feature-manifest.json). No private, unfiltered export is copied into this pass.

## Dataset

One user, one X6, two nights; all times below are Amman local. Rows retain the original Core/REM/Deep/Awake label, binary reference, packet identity, raw evidence, selector, availability, sparse vendor record IDs, and feature validity. Core/REM/Deep map to Sleep; Awake is the positive class.

| Night ending | Vendor interval | Core | REM | Deep | Awake | Total |
|---|---|---:|---:|---:|---:|---:|
| 27 Sep | 00:45–09:57 | 260 | 218 | 11 | 63 | 552 |
| 28 Sep | 23:30 previous day–08:35 | 273 | 221 | 48 | 3 | 545 |

There are 1,097 labeled minutes. Unlabeled captured context extends from session start minus 59 minutes through end plus 30 minutes, to support causal windows around the requested boundaries. Each night's context uses its own input archives. Outside-session minutes are never assigned Awake.

## Feature definitions

Scalar features: `raw_u8`, `is_0x80`, signed and absolute immediately adjacent-byte changes, and `distance_from_0x80_code = abs(raw_u8 - 128)`. The last quantity is an encoding-relative distance, not movement magnitude.

Trailing 3/5/10/30-minute windows include the current minute and require every exact consecutive minute to be `observedRawSignal`. Each exports mean, median, min, max, range, population standard deviation, fractions equal/not equal to 0x80, mean/max absolute adjacent change, transition count, and longest 0x80 run. Adjacent statistics use N−1 pairs. Missing, uninterpreted zero, or future bytes invalidate the relevant feature; observed counts and validity flags expose this. There is no filling, partial-window averaging, or gap bridging.

HR and SDNN require exactly one Da Halo observation starting at the exact minute, with the expected unit. No timestamp flooring, interval expansion, duplicate averaging, or carrying values. `has_hr`/`has_sdnn` and counts remain explicit. These are vendor observations, not newly decoded X6 samples. There is no oxygen feature.

## Evaluation design

Two whole-night folds: train 27/test 28 and train 28/test 27. No random row split, pooled threshold fitting, held-out tuning, prediction smoothing, or oversampling.

Always-Sleep is evaluated on all labeled rows and on every model's exact eligible test rows. Four single-feature thresholds maximize training balanced accuracy, then training Awake F1; remaining ties use a fixed candidate order. Both inequality directions are considered on training data only.

The compact movement logistic model uses `raw_u8`, `fraction_non_0x80_5m`, `mean_abs_delta_5m`, `raw_range_5m`, and `fraction_non_0x80_30m`. Training-only StandardScaler precedes logistic regression with C=1, balanced class weights, liblinear, seed 20260928, tolerance 1e-8, maximum 1,000 iterations, and fixed 0.5 cutoff. No parameter search. B adds exact HR; C adds exact HR and SDNN. Movement-only comparisons on the same B/C rows prevent coverage differences masquerading as sensor benefit.

Local Python 3.11, NumPy 2.3.5, SciPy 1.16.3, and scikit-learn 1.8.0 were already available; no dependencies were installed or added to the application. AUROC uses scores, AUPRC is non-interpolated average precision, specificity is Sleep recall, and undefined metrics are null with reasons. No fold-average headline is used.

## Class balance

| Night | All Sleep / Awake | Valid raw Sleep / Awake | Full 30m Sleep / Awake | Exact HR Sleep / Awake | Exact SDNN Sleep / Awake |
|---|---|---|---|---|---|
| 27 | 489 / 63 | 489 / 44 | 449 / 28 | 15 / 3 | 15 / 3 |
| 28 | 542 / 3 | 542 / 3 | 542 / 3 | 18 / 0 | 18 / 0 |

Nineteen first-night Awake minutes contain uninterpreted zero evidence. Complete 30-minute windows exclude 40 Sleep and 35 Awake minutes from that night; this is a material selection bias. The four 5-minute threshold cohorts contain 489 Sleep/36 Awake minutes on night 27. Night 28's three Awake minutes form one contiguous bout. Class weights cannot create independent evidence.

## Baseline results

Always predicting Sleep gives 99.45% accuracy on night 28 and 88.59% on all of night 27, with zero Awake recall and balanced accuracy 0.5. High accuracy is therefore insufficient.

| Feature | Rule trained on 27 | Held-out 28 balanced accuracy | Rule trained on 28 | Held-out 27 balanced accuracy |
|---|---|---:|---|---:|
| non-0x80 fraction, 5m | ≥0.6 | 0.4760 | ≤0 | 0.4046 |
| mean absolute change, 5m | ≥0.25 | 0.2159 | ≤0 | 0.4046 |
| max absolute change, 5m | ≥1 | 0.2159 | ≤0 | 0.4046 |
| raw range, 5m | ≥1 | 0.2159 | ≤0 | 0.4046 |

The direction reverses across training nights. All four miss all three held-out Awake minutes in the forward fold; reverse rules recover 8/36 with 202 false Awake predictions. Full support, scores, confusion matrices and metrics are in [single-feature-thresholds.json](analysis/sleep-detection-v0/single-feature-thresholds.json).

## Cross-night results

Primary movement logistic results, with confusion matrices ordered as true Sleep/Awake rows and predicted Sleep/Awake columns:

| Metric | Train 27 → test 28 | Train 28 → test 27 |
|---|---:|---:|
| Training Sleep / Awake | 449 / 28 | 542 / 3 |
| Test Sleep / Awake | 542 / 3 | 449 / 28 |
| Confusion matrix | [[458,84],[0,3]] | [[444,5],[28,0]] |
| Accuracy | 0.8459 | 0.9308 |
| Sleep recall / specificity | 0.8450 | 0.9889 |
| Awake recall | 1.0000 | 0.0000 |
| Sleep precision | 1.0000 | 0.9407 |
| Awake precision | 0.0345 | 0.0000 |
| Balanced accuracy | 0.9225 | 0.4944 |
| Awake F1 | 0.0667 | 0.0000 |
| Macro F1 | 0.4913 | 0.4821 |
| AUROC | 1.0000 | 0.7611 |
| AUPRC | 1.0000 | 0.1444 |

Perfect forward ranking concerns only three adjacent Awake minutes; at the fixed cutoff, 84 Sleep minutes are also called Awake. Reverse ranking exceeds chance, but the cutoff misses all 28 eligible Awake minutes. On that exact reverse cohort, Always-Sleep accuracy is 449/477 = 94.13%, exceeding the model's 93.08%.

B/C have only 14 Sleep/1 Awake eligible training rows on night 27 and 18 Sleep/0 Awake test rows on night 28. Both, and their matched movement-only comparisons, make two false Awake predictions on those 18 test rows. Awake recall, balanced accuracy, AUROC and AUPRC are undefined. Reverse B/C training contains only Sleep, so fitting is explicitly skipped. Neither HR nor SDNN benefit can be established.

Every run's complete metrics, exclusions, fitted parameters, and test row identities are in the two fold JSON files and [metrics.json](analysis/sleep-detection-v0/metrics.json); per-minute held-out predictions are in `predictions.csv`.

## Feature ablations

Common complete-case cohorts fix support at 449/28 for night 27 and 542/3 for night 28. Native-coverage results are also retained in `ablation.json`.

| Feature family | 27→28 balanced accuracy / Awake F1 | 28→27 balanced accuracy / Awake F1 |
|---|---|---|
| Raw byte only | 0.5821 / 0.0131 | 0.4853 / 0.1058 |
| 0x80-derived only | 0.3736 / 0 | 0.4313 / 0.0708 |
| Delta/transition only | 0.3782 / 0 | 0.4313 / 0.0708 |
| Rolling | 0.9317 / 0.0750 | 0.4911 / 0 |
| Combined movement | 0.9225 / 0.0667 | 0.4944 / 0 |

Rolling context improves the forward fold substantially but does not improve both directions. No winner is selected from these held-out comparisons.

## Transition analysis

All 91 vendor boundaries have individual −10…+10-minute exports: 1,911 rows before aggregation. Night 27 contains four Sleep→Awake, four Awake→Sleep, and 38 sleep-stage→sleep-stage boundaries. Night 28 contains zero, one, and 44 respectively. Overlapping windows are correlated.

At the boundary minute, first-night Sleep→Awake absolute byte changes have mean 48.67, median 8 and maximum 138 over only three valid pairs. This is strongly outlier-sensitive. Awake→Sleep mean change is 4.25 over four first-night events and zero at the only second-night event. Sleep-stage boundaries have mean changes 2.92 and 2.50. There is no second-night Sleep→Awake event to validate the first-night pattern. No lag was optimized.

Session start/end windows retain 244 individual rows. Comparing 30 minutes before start with start through +30, mean 5-minute non-0x80 fraction falls from 0.473 to 0.129 on night 27 and 0.600 to 0.097 on night 28. Around session end it rises from 0.278 to 0.742 and 0.293 to 0.987 among valid windows. This is an exploratory boundary association, not blind onset/wake detection: boundaries were supplied by the vendor, outside minutes are unlabeled, and valid-window coverage differs. After night 28's end only 20/31 raw minutes are valid; 11 zero/uninterpreted minutes and unusual low bytes prevent a physiological amplitude interpretation. Each statistic's actual count is exported in `session-boundary-summary.json`.

## Stage descriptives

`stage-descriptives.json` exports count, mean, median, quartiles/IQR, min/max, Cliff's delta, probability of superiority with half ties, and common-range overlap for each feature and night. Cliff's delta is P(first>second)−P(first<second), without an independence-based significance claim. Deep versus non-Deep includes Core, REM and Awake in the latter group.

Core versus REM raw-byte Cliff's delta is approximately 0.003 on each night. Rolling 30-minute non-0x80 fraction reverses direction (−0.178 to +0.152). Raw Deep versus non-Deep also reverses (+0.220 to −0.060). Rolling features do change part of the descriptive picture: Deep has lower 30-minute non-0x80 fraction (−0.300, −0.663) and standard deviation (−0.341, −0.855) on both nights, but only 11 and 48 Deep minutes and correlated windows support these estimates.

Awake versus Sleep 30-minute non-0x80 fraction (+0.636, +1.000) and standard deviation (+0.728, +0.995) show consistent positive associations in the available rows. Five-minute fraction reverses (+0.294, −0.568). The second night's initial Awake bout inherits pre-session context in the 30-minute windows; this may represent bedtime transition context rather than general wake detection. These observations justify further measurement, not Core/REM/Deep classification.

## Negative controls

Fixed seed 20260928 shuffles only eligible training labels, preserving support and keeping held-out labels unchanged. It is one sanity check, not a permutation p-value.

| Combined movement | 27→28 balanced accuracy / Awake F1 | 28→27 balanced accuracy / Awake F1 |
|---|---|---|
| Original labels | 0.9225 / 0.0667 | 0.4944 / 0 |
| Shuffled labels | 0.3017 / 0 | 0.6991 / 0.1909 |

Forward logistic performance collapses, but the reverse shuffled fit outperforms the original; its AUROC is 0.7646 versus 0.7611. Shuffled threshold balanced accuracies also exceed the original rules: 0.7841 forward and 0.5593–0.5954 reverse. The controls are **not consistently weaker**, undermining a robust signal claim.

Separate clock-only models yield balanced accuracies 0.1993 and 0.5589 on all labeled rows. Adding clock to movement yields 0.8810 and 0.4933 on movement-eligible rows, without consistent improvement. Minute-of-night uses vendor session start and is oracle schedule information, never a primary predictor. Weak clock-only results do not rule out schedule/context confounding.

## Limitations

Two nights from one wearer cannot support population inference. Three contiguous Awake minutes are not three independent events. Complete-case exclusions disproportionately remove Awake evidence; sparse HR/SDNN leave no second-night Awake rows. Vendor references are not clinical truth, raw byte semantics remain unknown, and annotations define the observation windows. Numerous descriptive features create opportunities for chance associations. The fixed shuffle does not estimate significance. A common sampling schedule and pre-session activity can drive apparent separation. No new physical-device validation occurred in this offline pass.

## What the evidence supports

The decision gate is answered without a composite score:

1. **Movement-only generalization:** not reliable in both directions; forward balanced accuracy 0.9225 contrasts with reverse 0.4944 and zero reverse Awake recall.
2. **Stable single feature:** no validated single-feature rule. Thirty-minute non-0x80 fraction and standard deviation have consistent descriptive direction, warranting prospective testing.
3. **Rolling improvement:** substantial forward improvement only; reverse failure remains.
4. **Exact HR benefit:** unknown; sparse held-out rows contain no Awake reference.
5. **Exact SDNN benefit:** unknown for the same reason; adding SDNN does not establish incremental benefit.
6. **Class imbalance:** explains very high trivial accuracy and makes favorable forward ranking fragile. It does not by itself explain every byte association, but prevents accuracy-based conclusions.
7. **Stronger than shuffle:** not consistently. Reverse logistic and threshold controls contradict that claim.
8. **Further collection:** yes, the repeatable direction of some long-window and boundary associations justifies collecting more nights with the same feature family, without claiming a validated model.
9. **Core/REM/Deep classification:** no supporting held-out evidence. Rolling Deep associations are exploratory; Core/REM separation remains weak/inconsistent.

## What the evidence does not support

No clinical sleep truth, production sleep samples, stage predictions, sleep score, Age/Recovery result, stable sleep/wake cutoff, physiological interpretation of `0213` amplitude, HR/SDNN advantage, or need for a more complex model has been established. Production archives, UI, HealthKit access, BLE behavior and schema remain unchanged.

## Recommended next capture protocol

This is a practical research collection target, not a statistical guarantee of sufficiency:

1. Collect **at least 20 additional nights** with the same wearer/X6 profile before considering a sequence/stage experiment. Use the first 15 for development and lock the final five before model selection. Seek at least **300 valid vendor-Awake minutes across ten or more nights**, at least **20 distinct Awake bouts**, and at least five nights with 15 or more Awake minutes. Include natural within-session awakenings, not only bedtime latency. Extend collection if those coverage targets are unmet; do not manufacture wakefulness or duplicate observations.
2. Before opening Da Halo each morning, save the VitaEpoch raw TX/RX archive and diagnostics with local date/time, timezone, device identity, firmware/profile, selectors, full response sequences, malformed frames and uninterpreted zeros. Capture history covering at least 60 minutes before the vendor session and 30 minutes after final wake where available. Preserve missingness if the band cannot supply it.
3. Across midnight, retain current-day `0213` pages intersecting midnight through wake/context, plus the previous-day page intersecting the pre-midnight window. For a 23:30 start, observed `0107` covers 21:00–23:59 and supplies the needed prior context. `0100` covers previous-day 00:00–02:59 and is not interchangeable. Use the existing planner and only physically observed/validated selectors; if a new schedule needs an unvalidated previous-day page, preserve the gap and validate that selector separately. Do not invent offsets above 1 or assume a full previous-day acquisition exists.
4. Sync existing HR/SDNN histories before switching to Da Halo, preserving all pages/chunks and raw timing evidence. Record empty/missing histories honestly; do not infer new commands to improve coverage. Keep subsequent vendor-export observations distinct from packet-decoded observations.
5. Afterward, sync Da Halo and export its Apple Health records for the dated night, including sleep stages and original HR/SDNN timestamps, durations, units and source provenance. Keep the private export outside version control; extract only scoped research records. Do not manufacture an overnight oxygen series.
6. Optional notes: approximate lights-off, known awakenings, final wake, removal/charging, unusual exercise/alcohol/illness, and device/app clock changes. These contextual notes are research aids, not mandatory production inputs.

Re-run the fixed baselines on new nights before adding sequence assumptions. Stage work also needs adequate representation of each vendor stage across nights and independent evaluation; clinical or population claims would require independent reference data and more wearers beyond this target.

## Changed files

- `Sources/X6Research/MovementContext.swift`: exports bounded, unlabeled captured movement context without creating health samples.
- `Sources/X6SleepAnalysis/main.swift`: optional `--export-movement-context`; existing outputs remain unchanged.
- `Tests/VitaEpochCoreTests/SleepResearchContextTests.swift`: two context/evidence/isolation tests.
- `scripts/sleep_detection_v0.py`: deterministic offline features, whole-night models, controls, descriptives, transitions and artifacts.
- `scripts/test_sleep_detection_v0.py`: 14 research tests covering calculations, leakage, exact alignment, missingness, metrics, shuffle, serialization and application isolation.
- `README.md`: research dependencies, commands and report link.
- `docs/SLEEP_DETECTION_V0_2026-09-28.md`: this report.
- All 19 new files under `docs/analysis/sleep-detection-v0/`: `dataset.csv` (labeled features); `feature-manifest.json` (definitions/provenance); `fold-27-to-28.json`, `fold-28-to-27.json`, `metrics.json` (evaluation/support); `single-feature-thresholds.json` (training-selected rules); `model-coefficients.json` (scalers/coefficients); `ablation.json`, `label-shuffle.json`, `time-leakage-check.json` (controls); `stage-descriptives.json` (distributions); `transition-windows.csv`, `transition-summary.json` (individual boundaries/aggregates); `session-boundary-windows.csv`, `session-boundary-summary.json` (unlabeled surrounding context); `movement-context-2026-09-27.json`, `movement-context-2026-09-28.json` (decoded evidence context); `predictions.csv` (held-out audit); `summary.md` (generated tables).

## Validation results

- `swift test`: **52 tests passed**, zero failures, including both new context tests.
- Research unittest discovery: **14 tests passed**.
- Full research pipeline run twice into separate directories: **all 19 output files byte-identical** in the recorded local dependency environment.
- Generic iOS Simulator build with `CODE_SIGNING_ALLOWED=NO`: **BUILD SUCCEEDED**.
- UI suite not run: no app-target files changed; the prompt makes this conditional on app-target changes.
- `git diff --check`: passed.
- SHA-256 comparison confirms previous analysis outputs, reports, capture fixtures, production code and Xcode project preserved. No raw evidence deleted; archive schema remains 3.

Reproduce with the commands in the README. These are offline research/test results, not a new claim of physical-X6 correctness.

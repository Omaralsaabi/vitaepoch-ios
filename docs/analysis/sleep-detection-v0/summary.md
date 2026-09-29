# Sleep Detection V0 — offline vendor-reference benchmark

Two nights from one X6/user. Labels are vendor reference, not clinical ground truth. No production sleep result is created.

| Night | Labeled Sleep / Awake | Valid movement Sleep / Awake | Valid trailing 30m Sleep / Awake | Exact HR Sleep / Awake | Exact SDNN Sleep / Awake |
|---|---|---|---|---|---|
| 2026-09-27 | 489 / 63 | 489 / 44 | 449 / 28 | 15 / 3 | 15 / 3 |
| 2026-09-28 | 542 / 3 | 542 / 3 | 542 / 3 | 18 / 0 | 18 / 0 |

## Held-out results

Raw confusion matrices, all requested metrics, eligibility exclusions and undefined reasons are in the fold/metrics JSON files. Always-Sleep is also evaluated on every model’s exact eligible test cohort. Thresholds/scalers use training rows only.

| Train → test | Baseline | Test Sleep / Awake | Accuracy | Awake recall | Balanced accuracy | Awake F1 | AUROC | AUPRC |
|---|---|---|---|---|---|---|---|---|
| 27 → 28 | always_sleep_all_labeled | 542 / 3 | 0.9945 | 0.0000 | 0.5000 | 0.0000 | 0.5000 | 0.0055 |
| 27 → 28 | threshold_fraction_non_0x80_5m | 542 / 3 | 0.9468 | 0.0000 | 0.4760 | 0.0000 | 0.2159 | 0.0055 |
| 27 → 28 | threshold_mean_abs_delta_5m | 542 / 3 | 0.4294 | 0.0000 | 0.2159 | 0.0000 | 0.2159 | 0.0055 |
| 27 → 28 | threshold_max_abs_delta_5m | 542 / 3 | 0.4294 | 0.0000 | 0.2159 | 0.0000 | 0.2159 | 0.0055 |
| 27 → 28 | threshold_raw_range_5m | 542 / 3 | 0.4294 | 0.0000 | 0.2159 | 0.0000 | 0.2159 | 0.0055 |
| 27 → 28 | A_movement | 542 / 3 | 0.8459 | 1.0000 | 0.9225 | 0.0667 | 1.0000 | 1.0000 |
| 27 → 28 | B_exact_vendor | 18 / 0 | 0.8889 | undefined | undefined | 0.0000 | undefined | undefined |
| 27 → 28 | A_on_B_same_rows | 18 / 0 | 0.8889 | undefined | undefined | 0.0000 | undefined | undefined |
| 27 → 28 | C_exact_vendor | 18 / 0 | 0.8889 | undefined | undefined | 0.0000 | undefined | undefined |
| 27 → 28 | A_on_C_same_rows | 18 / 0 | 0.8889 | undefined | undefined | 0.0000 | undefined | undefined |
| 28 → 27 | always_sleep_all_labeled | 489 / 63 | 0.8859 | 0.0000 | 0.5000 | 0.0000 | 0.5000 | 0.1141 |
| 28 → 27 | threshold_fraction_non_0x80_5m | 489 / 36 | 0.5619 | 0.2222 | 0.4046 | 0.0650 | 0.3529 | 0.0529 |
| 28 → 27 | threshold_mean_abs_delta_5m | 489 / 36 | 0.5619 | 0.2222 | 0.4046 | 0.0650 | 0.3916 | 0.0542 |
| 28 → 27 | threshold_max_abs_delta_5m | 489 / 36 | 0.5619 | 0.2222 | 0.4046 | 0.0650 | 0.4035 | 0.0564 |
| 28 → 27 | threshold_raw_range_5m | 489 / 36 | 0.5619 | 0.2222 | 0.4046 | 0.0650 | 0.3893 | 0.0557 |
| 28 → 27 | A_movement | 449 / 28 | 0.9308 | 0.0000 | 0.4944 | 0.0000 | 0.7611 | 0.1444 |
| 28 → 27 | B_exact_vendor | 14 / 1 | not_trainable_single_class | not_trainable_single_class | not_trainable_single_class | not_trainable_single_class | not_trainable_single_class | not_trainable_single_class |
| 28 → 27 | A_on_B_same_rows | 14 / 1 | not_trainable_single_class | not_trainable_single_class | not_trainable_single_class | not_trainable_single_class | not_trainable_single_class | not_trainable_single_class |
| 28 → 27 | C_exact_vendor | 14 / 1 | not_trainable_single_class | not_trainable_single_class | not_trainable_single_class | not_trainable_single_class | not_trainable_single_class | not_trainable_single_class |
| 28 → 27 | A_on_C_same_rows | 14 / 1 | not_trainable_single_class | not_trainable_single_class | not_trainable_single_class | not_trainable_single_class | not_trainable_single_class | not_trainable_single_class |

## Ablations and shuffle controls

No winner is selected using held-out outcomes. Same-cohort ablations are provided alongside native coverage to expose complete-case selection effects.

| Train → test | Experiment | Test Sleep / Awake | Balanced accuracy | Awake F1 |
|---|---|---|---|---|
| 27 → 28 | ablation_raw_byte_only | 542 / 3 | 0.5821 | 0.0131 |
| 27 → 28 | ablation_common_raw_byte_only | 542 / 3 | 0.5821 | 0.0131 |
| 27 → 28 | ablation_code_0x80_only | 542 / 3 | 0.3773 | 0.0000 |
| 27 → 28 | ablation_common_code_0x80_only | 542 / 3 | 0.3736 | 0.0000 |
| 27 → 28 | ablation_delta_only | 542 / 3 | 0.2952 | 0.0000 |
| 27 → 28 | ablation_common_delta_only | 542 / 3 | 0.3782 | 0.0000 |
| 27 → 28 | ablation_rolling | 542 / 3 | 0.9317 | 0.0750 |
| 27 → 28 | ablation_common_rolling | 542 / 3 | 0.9317 | 0.0750 |
| 27 → 28 | ablation_combined_movement | 542 / 3 | 0.9225 | 0.0667 |
| 27 → 28 | ablation_common_combined_movement | 542 / 3 | 0.9225 | 0.0667 |
| 28 → 27 | ablation_raw_byte_only | 489 / 44 | 0.4329 | 0.1268 |
| 28 → 27 | ablation_common_raw_byte_only | 449 / 28 | 0.4853 | 0.1058 |
| 28 → 27 | ablation_code_0x80_only | 489 / 36 | 0.4046 | 0.0650 |
| 28 → 27 | ablation_common_code_0x80_only | 449 / 28 | 0.4313 | 0.0708 |
| 28 → 27 | ablation_delta_only | 489 / 36 | 0.4046 | 0.0650 |
| 28 → 27 | ablation_common_delta_only | 449 / 28 | 0.4313 | 0.0708 |
| 28 → 27 | ablation_rolling | 449 / 28 | 0.4911 | 0.0000 |
| 28 → 27 | ablation_common_rolling | 449 / 28 | 0.4911 | 0.0000 |
| 28 → 27 | ablation_combined_movement | 449 / 28 | 0.4944 | 0.0000 |
| 28 → 27 | ablation_common_combined_movement | 449 / 28 | 0.4944 | 0.0000 |
| 27 → 28 | shuffle_threshold_fraction_non_0x80_5m | 542 / 3 | 0.7841 | 0.0250 |
| 27 → 28 | shuffle_threshold_mean_abs_delta_5m | 542 / 3 | 0.7841 | 0.0250 |
| 27 → 28 | shuffle_threshold_max_abs_delta_5m | 542 / 3 | 0.7841 | 0.0250 |
| 27 → 28 | shuffle_threshold_raw_range_5m | 542 / 3 | 0.7841 | 0.0250 |
| 27 → 28 | shuffle_A_movement | 542 / 3 | 0.3017 | 0.0000 |
| 28 → 27 | shuffle_threshold_fraction_non_0x80_5m | 489 / 36 | 0.5954 | 0.1595 |
| 28 → 27 | shuffle_threshold_mean_abs_delta_5m | 489 / 36 | 0.5593 | 0.1463 |
| 28 → 27 | shuffle_threshold_max_abs_delta_5m | 489 / 36 | 0.5665 | 0.1495 |
| 28 → 27 | shuffle_threshold_raw_range_5m | 489 / 36 | 0.5665 | 0.1495 |
| 28 → 27 | shuffle_A_movement | 449 / 28 | 0.6991 | 0.1909 |

The 28 Sep night contains only three contiguous Awake minutes. HR/SDNN have no Awake observations on that night, preventing meaningful two-direction multimodal evaluation. Class-weighted fits do not add independent Awake evidence. Shuffling is a deterministic sanity check, not a p-value. Clock controls use oracle session timing and must not be interpreted as wearable signal. No four-class stage model or prediction smoothing was run.

See `docs/SLEEP_DETECTION_V0_2026-09-28.md` for the evidence-based decision gate and next-capture protocol.

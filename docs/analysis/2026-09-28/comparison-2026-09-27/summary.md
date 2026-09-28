# One-night reference alignment

Da Halo -> Apple Health; export.zip; night ending 2026-09-27

Vendor-labeled intervals for reverse engineering only; not an independently validated clinical ground truth. No sleep stage inferred. Raw amplitudes have unknown meaning. Zero/future/missing positions are excluded from amplitude statistics. Sparse HR/SDNN/0211 candidates are not imputed.

552 labeled/window minutes. Blank HR or oxygen means unavailable, not zero.

| Stage | Minutes | Raw observations | Zero/uninterpreted | Raw 0x80 | Mean raw byte | SDNN points | Mean SDNN |
|---|---:|---:|---:|---:|---:|---:|---:|
| Core | 260 | 260 | 0 | 212 | 129.57 | 6 | 11.33 |
| REM | 218 | 218 | 0 | 180 | 129.56 | 3 | 10.33 |
| Deep | 11 | 11 | 0 | 7 | 134.36 | 0 | — |
| Awake | 63 | 44 | 19 | 29 | 128.07 | 1 | 13.00 |

## Export observations and coverage

Vendor HR/SDNN are separate offline export observations, not raw 020F/0210 packets. Each export interval contributes one point at its start; no interval expansion or interpolation. The JSON retains source file, record ID and interval end. Empty oxygen columns mean no exported series was available.

| Stage | Missing / future / zero | Raw 0x80 fraction (observed denominator) | Raw count/min/max/mean/median | Vendor HR count/min/max/mean/median | Vendor SDNN count/min/max/mean/median | 0211 / vendor oxygen points |
|---|---|---|---|---|---|---|
| Core | 0 / 0 / 0 | 0.8154 | 260 / 128.00 / 183.00 / 129.57 / 128.00 | 10 / 60.00 / 77.00 / 70.30 / 71.50 | 10 / 10.00 / 14.00 / 11.20 / 11.00 | 0 / 0 |
| REM | 0 / 0 / 0 | 0.8257 | 218 / 128.00 / 148.00 / 129.56 / 128.00 | 5 / 64.00 / 77.00 / 68.80 / 66.00 | 5 / 10.00 / 14.00 / 11.20 / 11.00 | 0 / 0 |
| Deep | 0 / 0 / 0 | 0.6364 | 11 / 128.00 / 154.00 / 134.36 / 128.00 | 0 / — / — / — / — | 0 / — / — / — / — | 0 / 0 |
| Awake | 0 / 0 / 19 | 0.6591 | 44 / 2.00 / 161.00 / 128.07 / 128.00 | 3 / 66.00 / 72.00 / 69.67 / 71.00 | 3 / 10.00 / 14.00 / 12.33 / 13.00 | 0 / 0 |

### Stage boundaries

Absolute raw-byte change across adjacent observed minutes at a vendor stage boundary versus within-stage pairs. Missing/zero/future pairs excluded; no spike threshold, lag search, classifier or causal claim.

45 of 46 boundaries have two observed movement positions. Boundary change count/min/max/mean/median: 45 / 0.00 / 138.00 / 6.09 / 0.00; within-stage change: 485 / 0.00 / 44.00 / 2.74 / 0.00. These descriptive comparisons do not establish a sleep-stage rule.

No classifier was trained. Reference labels are copied only into offline alignment rows. They never become VitaEpoch sleep results.

## Frame integrity

- Packet 6398C0B4-4CD9-5BB5-A841-E6941BD8C583: 186 bytes, declared 188. Rejected without padding; raw bytes retained.
- Packet 7AEB3D38-5153-5A8B-B67F-4A119C0EAA76: 186 bytes, declared 188. Rejected without padding; raw bytes retained.

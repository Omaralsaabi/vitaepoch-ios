# One-night reference alignment

Da Halo -> Apple Health; export 28 sep.zip; night ending 2026-09-28

Vendor-labeled intervals for reverse engineering only; not an independently validated clinical ground truth. No sleep stage inferred. Raw amplitudes have unknown meaning. Zero/future/missing positions are excluded from amplitude statistics. Sparse HR/SDNN/0211 candidates are not imputed.

545 labeled/window minutes. Blank HR or oxygen means unavailable, not zero.

| Stage | Minutes | Raw observations | Zero/uninterpreted | Raw 0x80 | Mean raw byte | SDNN points | Mean SDNN |
|---|---:|---:|---:|---:|---:|---:|---:|
| Core | 273 | 273 | 0 | 226 | 129.59 | 0 | — |
| REM | 221 | 221 | 0 | 184 | 129.70 | 0 | — |
| Deep | 48 | 48 | 0 | 43 | 129.21 | 0 | — |
| Awake | 3 | 3 | 0 | 3 | 128.00 | 0 | — |

## Export observations and coverage

Vendor HR/SDNN are separate offline export observations, not raw 020F/0210 packets. Each export interval contributes one point at its start; no interval expansion or interpolation. The JSON retains source file, record ID and interval end. Empty oxygen columns mean no exported series was available.

| Stage | Missing / future / zero | Raw 0x80 fraction (observed denominator) | Raw count/min/max/mean/median | Vendor HR count/min/max/mean/median | Vendor SDNN count/min/max/mean/median | 0211 / vendor oxygen points |
|---|---|---|---|---|---|---|
| Core | 0 / 0 / 0 | 0.8278 | 273 / 128.00 / 162.00 / 129.59 / 128.00 | 4 / 66.00 / 79.00 / 69.75 / 67.00 | 4 / 10.00 / 14.00 / 12.00 / 12.00 | 0 / 0 |
| REM | 0 / 0 / 0 | 0.8326 | 221 / 128.00 / 164.00 / 129.70 / 128.00 | 12 / 57.00 / 81.00 / 64.00 / 63.00 | 12 / 10.00 / 14.00 / 12.08 / 12.00 | 0 / 0 |
| Deep | 0 / 0 / 0 | 0.8958 | 48 / 128.00 / 149.00 / 129.21 / 128.00 | 2 / 57.00 / 61.00 / 59.00 / 59.00 | 2 / 11.00 / 14.00 / 12.50 / 12.50 | 0 / 0 |
| Awake | 0 / 0 / 0 | 1.0000 | 3 / 128.00 / 128.00 / 128.00 / 128.00 | 0 / — / — / — / — | 0 / — / — / — / — | 0 / 0 |

### Stage boundaries

Absolute raw-byte change across adjacent observed minutes at a vendor stage boundary versus within-stage pairs. Missing/zero/future pairs excluded; no spike threshold, lag search, classifier or causal claim.

45 of 45 boundaries have two observed movement positions. Boundary change count/min/max/mean/median: 45 / 0.00 / 15.00 / 2.44 / 0.00; within-stage change: 499 / 0.00 / 36.00 / 2.85 / 0.00. These descriptive comparisons do not establish a sleep-stage rule.

No classifier was trained. Reference labels are copied only into offline alignment rows. They never become VitaEpoch sleep results.

## Frame integrity

- Packet CD355D63-1507-5709-AD80-6C386031D1CD: 186 bytes, declared 188. Rejected without padding; raw bytes retained.
- Packet 913CFEEF-5808-568B-83EF-ABE46F15178B: 184 bytes, declared 188. Rejected without padding; raw bytes retained.
- Packet 951C0FBE-D5DA-50D3-BCF4-88DC124102CB: 182 bytes, declared 188. Rejected without padding; raw bytes retained.

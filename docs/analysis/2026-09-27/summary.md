# One-night reference alignment

Da Halo -> Apple Health; handoff transcription

Vendor-labeled intervals for reverse engineering only; not an independently validated clinical ground truth. No sleep stage inferred. Raw amplitudes have unknown meaning. Zero/future/missing positions are excluded from amplitude statistics. Sparse HR/SDNN/0211 candidates are not imputed.

552 labeled/window minutes. Blank HR or oxygen means unavailable, not zero.

| Stage | Minutes | Raw observations | Zero/uninterpreted | Raw 0x80 | Mean raw byte | SDNN points | Mean SDNN |
|---|---:|---:|---:|---:|---:|---:|---:|
| Core | 260 | 260 | 0 | 212 | 129.57 | 6 | 11.33 |
| REM | 218 | 218 | 0 | 180 | 129.56 | 3 | 10.33 |
| Deep | 11 | 11 | 0 | 7 | 134.36 | 0 | — |
| Awake | 63 | 44 | 19 | 29 | 128.07 | 1 | 13.00 |

No classifier was trained. Reference labels are copied only into offline alignment rows. They never become VitaEpoch sleep results.

## Frame integrity

- Packet 6398C0B4-4CD9-5BB5-A841-E6941BD8C583: 186 bytes, declared 188. Rejected without padding; raw bytes retained.
- Packet 7AEB3D38-5153-5A8B-B67F-4A119C0EAA76: 186 bytes, declared 188. Rejected without padding; raw bytes retained.

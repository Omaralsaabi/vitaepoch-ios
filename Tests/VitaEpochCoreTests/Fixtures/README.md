# Fixture provenance

`device-2026-09-26.json` is the app archive copied read-only from the paired iPhone during the correctness pass. It contains 35 raw packets and 16 old decoded records from two syncs. The app's peripheral UUID is replaced with `captured-X6-EDA75689`; packet IDs, timestamps, payload bytes, and decoded readings are unchanged.

Both syncs contain only one all-zero page `0000` for each of 020F, 0210, and 0216. This fixture does **not** contain the nonzero HRV/temperature sequence described by the user. Regression tests must not turn these empty pages into invented samples or claim that a nonzero captured sequence has been replayed.

The 0209 capture includes `5B D274B76A`. The user confirmed 91 bpm at 15:31, 26 September 2026, Amman (UTC+3). The raw field is 1790407890, or 07:31:30 UTC under the old Unix interpretation. Its captured seconds are retained, giving an expected corrected instant of 12:31:30 UTC / 15:31:30 Amman. This is a device/capture-day calibration, not proof of a universal X6 timestamp convention. No exact SpO₂ or stress Da Halo reference time was supplied; shared correction remains provisional.

`StabilityTests` and the populated UI test construct four-page HRV/temperature sequences using the user-provided value examples. Those synthetic fixtures test assembly, zeros, ordering, deduplication, persistence/querying, and UI. They are not additional real-device captures.

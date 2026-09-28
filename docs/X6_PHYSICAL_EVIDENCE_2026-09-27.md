# X6 physical evidence integration — 27 Sep 2026

Implemented from `prompts/CODEX_X6_PHYSICAL_EVIDENCE_SLEEP_PASS.md`, using the document as instructed. No new physical sync was performed. This report supersedes no historical record: `STABILITY_VALIDATION.md` and `DEVICE_VALIDATION.md` are byte-for-byte unchanged.

## Evidence and implementation

- **Captured fact:** The supplied complete `0210` page produces twelve nonzero readings: 13, 12, 12, 10, 14, 11, 11, 10, 10, 13, 11, 10 ms. Archive, queries, and simulator UI populate from it. The vendor export identifies SDNN for serial `EDA75689`, firmware `MOY-I4E3-1.1.6`. Samples store `hrvStatistic: sdnn` and `semanticEvidence` with source ID `da-halo-health-export-2026-09-27-hrv-sdnn`, serial and firmware. Unmatched profiles remain unknown; daily queries do not pool unknown HRV with SDNN. The vendor designation does not establish clinical accuracy.
- **Captured fact:** All four supplied `020B` readings match the vendor timestamps: 98% at 15:18:35, 97% at 15:20:11, 99% at 15:25:02, 99% at 18:36:46 on 26 Sep, UTC+3. Timestamp evidence now has `independentlyConfirmedVendorExport`, scoped to the known device, date, and four raw timestamps. The +18,000-second correction is not global. Stress remains provisional. Original raw timestamps and bytes remain stored.
- **Provisional interpretation:** The temperature words decode as 36.3, 36.2, 36.4, and 36.1 °C in constructed full-frame tests. The document supplies no full `0216` frame, so physical temperature archive/query/UI population cannot be established from this evidence. Excerpts remain raw; no synthetic frame is presented as physical evidence. The metric remains Wrist Temperature with provisional semantic metadata.
- **Strong inference:** Current-day `0213` page n contains 180 raw minute positions beginning at n × 180 minutes. Raw amplitude meaning remains **unknown**. The decoder preserves the entire byte range, including values below 0x80, without subtraction or stage mapping.

## Movement transport and storage

A DEBUG diagnostics action sends the single observed `FDDA100802130000` request. It waits for pages `0000` through `0007`; it does not send eight page requests. Valid empty pages count as received, and all eight complete the request. Missing pages remain partial with exact receipt and timeout diagnostics. This command is not added to the routine seven-request sync.

Each valid page contributes exactly 180 positions. Storage deduplicates by device, local day, and minute offset, handles out-of-order/replayed pages, and records packet ID, timezone, decoder version, raw byte, page/index, and semantic evidence. Zero values are uninterpreted; positions after receipt time are future, not observed activity. Unsupported day variants are rejected. No health score or sleep stage is inferred.

**Document discrepancy:** Pages `0006` and `0007` contain 186 bytes each, while declaring 188. Their bytes are preserved and rejected without padding or borrowing bytes from the next frame. The six valid pages supply 1,080 positions; this physical transcription remains partial, missing valid pages 6 and 7. Constructed complete-burst tests separately establish all 1,440 positions and transport completion. The supplied complete pages cover the entire sleep reference window.

The three previously incomplete requests were **020F periodic HR, 0210 HRV, and 0216 wrist temperature**, each requested at `0000`; the old iPhone archive contained only an all-zero `0000` reply for each and no later pages. HRV/temperature retain automatic-burst waiting, then missing observed-variant requests after a quiet interval. Empty pages are transport receipts. `020F` continuation remains unresolved; no speculative continuation shape was introduced. This document has one complete HRV page, not full later-page bytes, so the app's full continuation behavior remains unvalidated physically.

## Migration and preservation

Archive schema changes from 2 to 3 to persist minute movement and semantic evidence. A schema-2 migration writes an exact `archive.before-v3.json` backup before replay. Existing `archive.before-v2.json` is untouched; older schema-1 input retains its established backup behavior. Raw packets, malformed frames, old decodes, and unknown features are retained. Tests cover backup equality, idempotent migration, replay/relaunch deduplication, and raw packet retention.

The physical fixture is explicitly a handoff transcription, not a newly obtained iPhone archive. Receipt time 18:58 +03:00 is an approximate analysis anchor; it is not an exact timestamp for every notification. Source/frame hashes and lengths are in the fixture manifest. The negative `020E` requests and unknown `0212` excerpts remain evidence only. No FDD5 writes or speculative sleep requests were added. FDD1 support remains intact.

## One-night offline analysis

`Sources/X6Research` and the `x6-sleep-analysis` executable are development-only package targets, excluded from the iOS app. The utility joins exact minute timestamps, without interpolation, with periodic HR (`020F`), confirmed SDNN (`0210`), and optional explicitly annotated `0211` candidates. It copies the 47 supplied vendor intervals into the offline `groundTruthStage` column only. These are reference labels for reverse engineering, not independently validated clinical truth or production sleep results.

Generated output: [summary](analysis/2026-09-27/summary.md), [CSV](analysis/2026-09-27/alignment.csv), [JSON](analysis/2026-09-27/alignment.json), [statistics](analysis/2026-09-27/statistics.json).

| Reference stage | Minutes | Nonzero raw observations | Zero/uninterpreted | Raw 0x80 | SDNN points |
|---|---:|---:|---:|---:|---:|
| Core | 260 | 260 | 0 | 212 | 6 |
| REM | 218 | 218 | 0 | 180 | 3 |
| Deep | 11 | 11 | 0 | 7 | 0 |
| Awake | 63 | 44 | 19 | 29 | 1 |

There are 552 aligned minutes (00:45–09:57), 489 asleep reference minutes and 63 awake reference minutes. Ten SDNN points fall inside the window; two precede it. No periodic HR or `0211` data were supplied for this night, so those cells remain blank. Raw 0x80 occurs under every stage. No classifier, threshold rule, baseline, or production sleep algorithm was built. Sleep UI reads “Awaiting protocol/model validation”.

## Validation

- `swift test`: **32 passed, zero failures** on 27 Sep 2026.
- Generic iOS Simulator `xcodebuild ... CODE_SIGNING_ALLOWED=NO build`: **succeeded**.
- Simulator `xcodebuild ... test`, iPhone 17 Pro: **4 UI tests passed**, including scoped SDNN rendering, Day/Week querying, navigation, safe area, and empty/populated archive behavior.
- Offline CLI: **552 rows generated**, totals checked against all 47 reference intervals.
- `git diff --check`: passed. Historical validation-report hashes unchanged.

Local run artifacts: `/private/tmp/vitaepoch-physical-20260927/` (core/build/UI logs and `ui-tests.xcresult`). No installation, radio sync, or device correctness claim follows from simulator tests.

## Remaining unknowns

Full temperature framing and later HRV/temperature page sequences are absent from the supplied document. Movement pages 6/7 are short. Exact movement amplitude meaning, previous-day movement variants, `020F` continuation, `0211` semantics, `0212`, stress timestamp confirmation, and a validated sleep model remain unknown or provisional as described above. The implementation does not infer answers from coincidental values or one night's labels.

## Needs physical X6 revalidation

1. Install the new build on the paired iPhone; verify FDD3 subscription completes before history requests.
2. Sync real nonzero HRV/temperature; compare several SDNN values/times with the vendor export and verify Wrist Temperature remains provisional after relaunch.
3. Check manual HR and all four known SpO₂ timestamps; independently validate stress before promoting its evidence.
4. Capture the one-request `0213` burst, confirm complete frame lengths and all eight pages, and verify 1,440 represented positions with future values excluded from observed activity.
5. Confirm valid empty pages complete transport, missing pages remain explicit, and actual HRV/temperature continuation works. Keep `020F` partial if continuation is absent.
6. Replay/reconnect/relaunch without duplicate minute records; verify lossless on-device migration and backups, including malformed/unknown raw evidence.
7. Recheck chart ranges, content clearance, and console responsiveness on the physical phone. Simulator results do not establish radio behavior or eliminate device-only console issues.

## Exact changed-file list for this pass

Each file below changed or was created during this pass; unchanged files from the prior stability pass are excluded.

- `Package.swift` — Adds the development-only research library and alignment executable.
- `README.md` — Documents the new evidence report and offline utility invocation.
- `Sources/VitaEpochCore/ArchiveWorker.swift` — Migrates to schema 3 with an exact pre-migration backup and semantic replay.
- `Sources/VitaEpochCore/Domain.swift` — Stores optional HRV statistic, semantic provenance, and capture provenance.
- `Sources/VitaEpochCore/LocalArchive.swift` — Adds schema 3 movement storage and minute-position deduplication.
- `Sources/VitaEpochCore/MetricQueries.swift` — Keeps HRV aggregation scoped to one device/statistic.
- `Sources/VitaEpochCore/MovementHistory.swift` — Decodes current-day raw minute positions with explicit zero/future availability.
- `Sources/VitaEpochCore/PacketProcessor.swift` — Routes movement, carries semantic evidence, and strictly validates document frame boundaries.
- `Sources/VitaEpochCore/SemanticEvidence.swift` — Defines semantic status and the verified serial/firmware SDNN profile.
- `Sources/VitaEpochCore/SyncDiagnostics.swift` — Tracks all eight movement pages without adding per-page movement writes.
- `Sources/VitaEpochCore/TimestampEvidence.swift` — Adds independently confirmed vendor-export evidence for the four matched SpO₂ records.
- `Sources/VitaEpochCore/X6Protocol.swift` — Annotates scoped SDNN/provisional wrist temperature; adds the observed movement request.
- `Sources/X6Research/SleepAlignment.swift` — Aligns sparse observations with supplied reference intervals and computes descriptive statistics.
- `Sources/X6SleepAnalysis/main.swift` — Provides the read-only archive analysis CLI and output formatting.
- `Tests/VitaEpochCoreTests/ArchiveWorkerTests.swift` — Verifies schema 3 backup/migration and movement replay/relaunch preservation.
- `Tests/VitaEpochCoreTests/Fixtures/physical-2026-09-27/README.md` — Documents transcription provenance, approximate receipt anchor, and incomplete evidence.
- `Tests/VitaEpochCoreTests/Fixtures/physical-2026-09-27/capture.json` — Stores supplied physical frames/excerpts and negative attempts without repairing bytes.
- `Tests/VitaEpochCoreTests/Fixtures/physical-2026-09-27/frames-verbatim.txt` — Preserves the original supplied complete-frame text lines.
- `Tests/VitaEpochCoreTests/Fixtures/physical-2026-09-27/manifest.json` — Records source/frame hashes, lengths, and evidence limitations.
- `Tests/VitaEpochCoreTests/Fixtures/physical-2026-09-27/sleep-reference.json` — Stores the 47 vendor intervals as offline reference labels only.
- `Tests/VitaEpochCoreTests/PhysicalEvidenceTests.swift` — Tests physical HRV/SpO₂/movement, constructed transport cases, scoped semantics, and offline alignment.
- `Tests/VitaEpochCoreTests/StabilityTests.swift` — Updates only the evidence-status assertion for independently confirmed SpO₂.
- `UITests/VitaEpochUITests.swift` — Adds physical SDNN UI validation and deterministic fixture query dates.
- `VitaEpoch.xcodeproj/project.pbxproj` — Registers new app core files and physical UI-test fixture resources.
- `VitaEpoch/BLE/X6CentralManager.swift` — Adds DEBUG-only single-request movement capture using existing sync tracking.
- `VitaEpoch/Storage/AppStore.swift` — Supports a deterministic optional query date for fixture UI tests.
- `VitaEpoch/UI/Components.swift` — Selects SDNN title/explanation from sample evidence.
- `VitaEpoch/UI/DeviceView.swift` — Exposes diagnostic movement capture/readiness and updated protocol evidence copy.
- `VitaEpoch/UI/MetricDetailView.swift` — Displays scoped SDNN and independently confirmed SpO₂ evidence.
- `VitaEpoch/UI/RootTabView.swift` — Uses protocol/model-validation sleep copy and scoped HRV input copy; no formula change.
- `VitaEpoch/VitaEpochApp.swift` — Reads the DEBUG-only test query clock.
- `docs/X6_PHYSICAL_EVIDENCE_2026-09-27.md` — Records this pass, every changed file, validation results, and remaining physical checks.
- `docs/analysis/2026-09-27/alignment.csv` — 552 minute rows for inspection.
- `docs/analysis/2026-09-27/alignment.json` — Structured sparse alignment rows.
- `docs/analysis/2026-09-27/statistics.json` — Structured per-stage descriptive statistics.
- `docs/analysis/2026-09-27/summary.md` — Human-readable one-night statistics and frame-integrity findings.
- `scripts/generate_project.py` — Includes physical fixture resources in the UI-test target.

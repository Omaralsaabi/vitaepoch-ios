# X6 physical revalidation — 28 Sep 2026

Implemented the new addendum on top of the completed 27 Sep pass. The original validation reports and `docs/analysis/2026-09-27/` remain byte-for-byte unchanged. No sleep classifier, Age/Recovery formula, production HealthKit dependency, unknown sleep command, or FDD5 write was added.

## Physically validated on 28 Sep

These transport observations are **reported physical VitaEpoch/nRF evidence in the user’s addendum**, not new radio operations performed during this implementation. Device scope is serial `EDA75689`, firmware `MOY-I4E3-1.1.6`. The addendum reports 162 archived packets, 655 decoded records, decoder `x6-v0.3`; the provided ZIPs are Apple Health exports, not the VitaEpoch diagnostics archive, so those totals cannot be independently recounted here.

| Path | Reported physical outcome | Status |
|---|---|---|
| VitaEpoch connection | Updated app connected to the matched X6 | Physically validated in reported session |
| `0210` | Selectors 0000/0001/0002/0003; 152-byte replies; 12/5/0/0 decoded records; completion repeated | Existing missing-page continuation physically validated on this profile; empty pages succeed |
| `0216` | Same selectors and lengths; 72/30/0/0 records; completion repeated | Continuation and nonzero ingestion physically validated; Wrist Temperature semantics remain provisional |
| `020F` | TX `FDDA1007020F00`; only page 0000, 17 records; page 0001 absent | Still partial; no validated continuation selector |
| VitaEpoch `0213` | Two initial requests yielded only page 0000; timeouts 9.380 and 9.494 seconds | Automatic burst alone was unreliable |
| nRF `0213` | Explicit `FDDA100802130001` through `...0007` each returned matching page | Current-day fallback selectors physically observed; new VitaEpoch orchestration still needs a radio run |
| `0213` time grid | Noon capture: page 4 begins with three nonzero positions; later reported pages zero | Independently supports 180-minute pages and n × 180 local-minute offsets; amplitude meaning remains unknown |

Scoped SDNN semantics are unchanged. The original export independently contains the vendor SDNN type and the 47 first-night stage intervals exactly matching the prior transcription. Full response payloads for the new HRV/temperature sequence are not in the addendum or Apple Health exports. Regression coverage therefore explicitly replays **reported receipt metadata** for 12/5/0/0 and 72/30/0/0; it does not label constructed payload bodies as physical captures. The old captured-HRV decoding and constructed temperature decoding tests remain intact.

## New `0213` acquisition behavior

The DEBUG current-day capture now uses an injected-time, regression-tested state machine:

1. Send `FDDA100802130000` once.
2. Collect automatic pages; after valid replies, allow an 800 ms quiet window. If the initial page never arrives, allow up to eight seconds before proceeding.
3. If all eight valid pages arrived, finish immediately with no fallback writes.
4. Otherwise request only missing, physically observed selectors `0001...0007`, in ascending order, each at most once. Never resend 0000 or request an already received page.
5. Wait up to eight seconds for the outstanding selector. A reply for another page is retained but does not prematurely advance the outstanding request. After its reply/quiet interval or timeout, advance to the next missing selector.
6. Finish complete only if all eight valid pages arrived. Otherwise keep the exact missing list. A 72-second overall bound also covers write backpressure or prolonged bursts; duplicates cannot extend a per-write wait indefinitely.

The CoreBluetooth driver uses this same pure state-machine decision function. Write backpressure waits without recording unsent writes. Disconnect cancels pending capture work through the existing lifecycle. Automatic/out-of-order/duplicate/empty pages remain valid, and storage deduplicates minute positions. `020F` receives no new write shape. Routine production sync is unchanged; movement stays a diagnostic/research capture.

Diagnostics display received pages and represented position count. Each RX is labeled “automatic after initial request” or “after explicit fallback” from persisted selector and TX/RX timing. A delayed automatic reply after an explicit write cannot be causally distinguished, so the label deliberately describes timing rather than claiming certainty. Raw requests and responses remain separate evidence.

## Exact physical bytes and discrepancy

The new fixture preserves all eight movement lines exactly, including values below 0x80 near the page 2/3 boundary. It is a document transcription combining the reported app/nRF observations, not a fabricated single-session automatic burst. Its 12:03 +03:00 receipt anchor is approximate; actual per-notification timing was not supplied.

| Page | Actual bytes | Declared bytes | Decoder handling |
|---|---:|---:|---|
| 0000 | 188 | 188 | 180 positions |
| 0001 | 188 | 188 | 180 positions |
| 0002 | 188 | 188 | 180 positions |
| 0003 | 188 | 188 | 180 positions |
| 0004 | 186 | 188 | Rejected; exact raw bytes retained |
| 0005 | 184 | 188 | Rejected; exact raw bytes retained |
| 0006 | 188 | 188 | 180 future/unobserved zero positions |
| 0007 | 182 | 188 | Rejected; exact raw bytes retained |

No padding, borrowing from another frame, or frame-length repair was performed. The exact fixture yields 900 represented positions and remains partial with missing valid pages **0004, 0005, 0007**. Separate explicitly constructed transport tests cover valid complete eight-page responses and empty future pages. These transcription limits do not contradict the reported successful radio replies; they limit what the supplied bytes can independently prove. Pages 0–2 fully cover the post-midnight sleep window.

## Archive/schema

**Schema remains 3; no migration is required.** Production persisted models did not change. Acquisition labels are computed from existing writes/responses; movement storage, packet evidence, backup behavior, timestamp rules, and replay remain intact. New vendor observation models belong only to `X6Research`, excluded from the app target. No HealthKit entitlement or runtime access was added.

## Export scope and second-night alignment

User mapping honored: `export.zip` is the 27 Sep export; `export 28 sep.zip` is the 28 Sep export. The extractor streams only `apple_health_export/export.xml`, filtering source name **Da Halo** and the requested overnight session’s sleep, HR, SDNN, and oxygen records. No unrelated source, workout route, ECG, or other Health data is copied into the repository. Each output records the ZIP SHA-256, source entry, filter, dates and record provenance. Original ZIPs remain untouched.

[28 Sep reference](analysis/2026-09-28/sleep-reference.json) contains **46 intervals**, 23:30 on 27 Sep through 08:35 on 28 Sep. The vendor totals are reproduced: **545 minutes in bed, 542 asleep, 3 awake; Core 273, REM 221, Deep 48**. “Core” is the export label corresponding to the app’s Light label. Score/efficiency/latency summaries were not turned into production metrics.

[CSV](analysis/2026-09-28/alignment.csv), [JSON](analysis/2026-09-28/alignment.json), [statistics](analysis/2026-09-28/statistics.json), and [summary](analysis/2026-09-28/summary.md) contain 545 minute rows. The first **30 minutes are explicitly missing movement**: 19 Core, 8 REM, 3 Awake. All **515 post-midnight minutes** have observed raw movement. No previous-day selector or imputation was used.

| Stage | Labeled / observed / missing minutes | Raw min / max / mean / median | Raw 0x80 count / observed fraction | Vendor HR count / mean | Vendor SDNN count / mean |
|---|---|---|---|---|---|
| Core | 273 / 254 / 19 | 128 / 162 / 129.610 / 128 | 210 / 0.8268 | 4 / 69.75 bpm | 4 / 12.00 ms |
| REM | 221 / 213 / 8 | 128 / 164 / 129.761 / 128 | 176 / 0.8263 | 12 / 64.00 bpm | 12 / 12.083 ms |
| Deep | 48 / 48 / 0 | 128 / 149 / 129.208 / 128 | 43 / 0.8958 | 2 / 59.00 bpm | 2 / 12.50 ms |
| Awake | 3 / 0 / 3 | unavailable | 0 / unavailable | 0 / unavailable | 0 / unavailable |

Full HR/SDNN min/max/median and all missing/future/zero counts are in the statistics/summary outputs. There are 18 HR and 18 SDNN export observations on each night. They remain **separate vendor observations**, not purported decoded `020F`/`0210` packets; each contributes one point at its export start, with its interval end retained. No five-minute record is expanded into five independent measurements. Neither overnight export has Da Halo oxygen records, and no `0211` candidate series was supplied. The displayed 98% vendor oxygen summary is not converted into minute data.

## Cross-night comparison

The enhanced first-night rerun is saved under `analysis/2026-09-28/comparison-2026-09-27/`, leaving the original first-night artifacts unchanged. See the [comparison](analysis/2026-09-28/cross-night-comparison.md) and [machine-readable comparison](analysis/2026-09-28/cross-night-comparison.json).

- **Core/REM movement:** Means are 129.573/129.560 on 27 Sep and 129.610/129.761 on 28 Sep; medians are all 128. Means nearly coincide, ranges overlap, and the tiny mean ordering reverses. No useful separation is established.
- **Deep movement:** Mean is 134.364 on the first night and 129.208 on the second, changing from above to below Core/REM. The direction reverses; the first night contains only 11 Deep minutes.
- **Awake:** First-night raw values overlap sleep, with 19 zero/uninterpreted minutes excluded. Second-night Awake has no movement coverage at all. Separation across nights is untestable from this evidence.
- **SDNN:** Vendor Core/REM means are both 11.20 ms on the first night and 12.00/12.083 ms on the second, with overlapping 10–14 ms ranges. No meaningful stable separation is established. Deep has zero first-night and two second-night observations; Awake has no second-night observations.
- **HR:** Vendor Core exceeds REM by 1.50 bpm then 5.75 bpm, but ranges overlap. Deep’s lower second-night HR rests on two points with no first-night counterpart. This is a candidate association for more captures, not validated discrimination.
- **Stage boundaries:** Exact adjacent observed-minute absolute raw changes average 6.089 at boundaries versus 2.740 within stages on 27 Sep; 2.619 versus 2.911 on 28 Sep. All medians are zero. The first-night maximum boundary change is 138 and influences its mean. The direction reverses; no stable boundary-spike association is shown. No threshold or lag search was fitted.
- **0x80:** Core/REM frequencies remain around 0.82; Deep changes from 0.636 to 0.896, reversing its ordering. There is no consistent stage-specific byte code.

These are descriptive, correlated within-person samples from two nights, not independent clinical validation. **Insufficient evidence for production sleep staging.** Sleep UI remains “Awaiting protocol/model validation”.

## Validation results

- `swift test`: **43 tests passed, zero failures** (the existing 32 plus 11 new regression tests).
- Generic iOS Simulator build: **BUILD SUCCEEDED**.
- Existing iPhone 17 Pro simulator UI suite: **4 passed, zero failures**.
- Both nightly CLI runs completed. Repeated runs of CSV/JSON/statistics/summary/transitions and cross-night comparison were **byte-identical**.
- The old first-night CLI invocation reproduced all four historical outputs **byte-for-byte** without vendor augmentation.
- Original three validation reports and first-night analysis files: unchanged hashes.
- `git diff --check`: passed.

Tests cover initial-only, partial/full automatic bursts, serialized missing-page fallback, same-capture provenance, at-most-once writes, zero future pages, duplicates/out-of-order replies, exact partial lists, no response/overall deadline, unrelated-device rejection, physical byte integrity, reported HRV/temperature receipt metadata, unresolved `020F`, midnight gaps, sparse vendor separation and no production sleep result. Local logs and the UI result bundle are under `/private/tmp/vitaepoch-revalidation-20260928/`.

## Still provisional / unknown

Raw `0213` amplitude meaning and previous-day selector; production sleep detection/staging; `020F` continuation; `0211` semantics; `0212`; independent stress timestamp confirmation; biological meaning and accuracy of Wrist Temperature. No new evidence promotes those claims. Complete new HRV/temperature response payloads and exact movement notification times were not supplied in this addendum/export pair.

## Needs another physical X6 validation

1. Run the updated DEBUG movement capture in VitaEpoch on the matched X6; confirm initial burst collection followed by only missing selectors, all-eight-page completion including empty future pages, and no fallback for a complete automatic burst.
2. Preserve exact raw replies and verify automatic/fallback diagnostic timing, bounded missing-page behavior, and reconnect/relaunch deduplication after this acquisition change.

The already reported HRV/temperature continuation does not need to be relabeled unvalidated merely because movement acquisition changed. No new physical install/sync was performed by this implementation session.

## Exact changed-file list

- `README.md` — Adds revalidation/report links and export-aware offline analysis usage.
- `Sources/VitaEpochCore/SyncDiagnostics.swift` — Adds bounded movement decisions and computed RX acquisition provenance; rejects other-device receipts.
- `Sources/X6Research/SleepAlignment.swift` — Keeps vendor export observations separate, validates their provenance, and computes descriptive stage-boundary changes.
- `Sources/X6SleepAnalysis/main.swift` — Adds optional vendor observations, coverage/statistics output, separate CSV columns and transition output.
- `Tests/VitaEpochCoreTests/Fixtures/physical-2026-09-28/README.md` — Explains physical transcription versus reported metadata versus vendor research inputs.
- `Tests/VitaEpochCoreTests/Fixtures/physical-2026-09-28/capture.json` — Preserves eight raw physical movement transcriptions with provenance and an approximate time anchor.
- `Tests/VitaEpochCoreTests/Fixtures/physical-2026-09-28/frames-verbatim.txt` — Retains all eight supplied frame text lines unchanged.
- `Tests/VitaEpochCoreTests/Fixtures/physical-2026-09-28/manifest.json` — Records prompt/frame hashes, exact lengths and limitations.
- `Tests/VitaEpochCoreTests/Fixtures/physical-2026-09-28/reported-sync-sequences.json` — Stores the addendum’s physical diagnostic counts/selectors without inventing response payloads.
- `Tests/VitaEpochCoreTests/Fixtures/physical-2026-09-28/sleep-reference.json` — Packages the 46 second-night export intervals for regression testing.
- `Tests/VitaEpochCoreTests/Fixtures/physical-2026-09-28/vendor-observations.json` — Packages separately sourced HR/SDNN observations for regression testing.
- `Tests/VitaEpochCoreTests/RevalidationTests.swift` — Adds 11 regression tests for fallback, raw fixtures, reported receipt sequences, midnight coverage and research boundaries.
- `VitaEpoch/BLE/X6CentralManager.swift` — Drives the movement fallback state machine with bounded waits and CoreBluetooth backpressure handling.
- `VitaEpoch/UI/DeviceView.swift` — Explains fallback behavior and displays received pages, represented positions and per-response acquisition timing.
- `docs/X6_PHYSICAL_REVALIDATION_2026-09-28.md` — Records evidence distinctions, transport behavior, schema status, tests, research findings and remaining radio checks.
- `docs/analysis/2026-09-28/alignment.csv` — Second night: Minute rows with explicit coverage, source IDs and separate vendor columns.
- `docs/analysis/2026-09-28/alignment.json` — Second night: Structured alignment with packet and vendor provenance.
- `docs/analysis/2026-09-28/comparison-2026-09-27/alignment.csv` — First-night export-enhanced rerun: Minute rows with explicit coverage, source IDs and separate vendor columns.
- `docs/analysis/2026-09-28/comparison-2026-09-27/alignment.json` — First-night export-enhanced rerun: Structured alignment with packet and vendor provenance.
- `docs/analysis/2026-09-28/comparison-2026-09-27/export-provenance.json` — First-night export-enhanced rerun: ZIP hash, entry, filter and extraction scope.
- `docs/analysis/2026-09-28/comparison-2026-09-27/selected-export-records.json` — First-night export-enhanced rerun: Only the relevant Da Halo sleep/HR/SDNN/oxygen source records.
- `docs/analysis/2026-09-28/comparison-2026-09-27/sleep-reference.json` — First-night export-enhanced rerun: Export-derived vendor stage intervals for offline alignment.
- `docs/analysis/2026-09-28/comparison-2026-09-27/statistics.json` — First-night export-enhanced rerun: Per-stage coverage and packet/vendor descriptive statistics.
- `docs/analysis/2026-09-28/comparison-2026-09-27/summary.md` — First-night export-enhanced rerun: Readable coverage, full descriptive statistics and malformed-frame findings.
- `docs/analysis/2026-09-28/comparison-2026-09-27/transitions.json` — First-night export-enhanced rerun: Adjacent-minute boundary versus within-stage change statistics.
- `docs/analysis/2026-09-28/comparison-2026-09-27/vendor-observations.json` — First-night export-enhanced rerun: Sparse export observations retaining source, record and interval.
- `docs/analysis/2026-09-28/cross-night-comparison.json` — Two-night descriptive comparison and limitations; no classifier.
- `docs/analysis/2026-09-28/cross-night-comparison.md` — Two-night descriptive comparison and limitations; no classifier.
- `docs/analysis/2026-09-28/export-provenance.json` — Second night: ZIP hash, entry, filter and extraction scope.
- `docs/analysis/2026-09-28/selected-export-records.json` — Second night: Only the relevant Da Halo sleep/HR/SDNN/oxygen source records.
- `docs/analysis/2026-09-28/sleep-reference.json` — Second night: Export-derived vendor stage intervals for offline alignment.
- `docs/analysis/2026-09-28/statistics.json` — Second night: Per-stage coverage and packet/vendor descriptive statistics.
- `docs/analysis/2026-09-28/summary.md` — Second night: Readable coverage, full descriptive statistics and malformed-frame findings.
- `docs/analysis/2026-09-28/transitions.json` — Second night: Adjacent-minute boundary versus within-stage change statistics.
- `docs/analysis/2026-09-28/vendor-observations.json` — Second night: Sparse export observations retaining source, record and interval.
- `scripts/compare_sleep_nights.py` — Regenerates the specifically scoped 27/28 Sep descriptive comparison without fitting a model.
- `scripts/extract_sleep_reference.py` — Streams only the scoped Da Halo night records and records export provenance.

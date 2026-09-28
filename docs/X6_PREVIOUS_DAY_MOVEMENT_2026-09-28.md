# X6 previous-day movement — 28 Sep 2026

Narrow follow-up to the completed revalidation pass, based on `prompts/CODEX_X6_PREVIOUS_DAY_MOVEMENT_ADDENDUM.md`. Previous validation reports are unchanged. The requested second-night research artifacts were regenerated with additional physical evidence. No Age/Recovery, icon, archive-migration, or production sleep feature work was performed.

## Captured fact

The supplied nRF physical-capture transcription contains two exact complete 188-byte replies, with 180 raw positions each, for serial `EDA75689`, firmware `MOY-I4E3-1.1.6`:

- Request `FDDA100802130100` → reply selector `0100`. The entire value payload matches the prior 27 Sep current-day page-0 capture byte-for-byte.
- Request `FDDA100802130107` → reply selector `0107`. It supplies 21:00–23:59 on 27 Sep; its last 30 positions cover the formerly missing 23:30–23:59 window.

The fixtures retain exact frame text, bytes, reported request hex, device profile, source hashes and confidence. The physical capture date is supplied; exact notification times are not. The 12:03 +03:00 receipt anchor is explicitly approximate and used only to recover the known local day. No request timing, packet contents or sleep measurements were fabricated.

## Strongly supported interpretation and implemented bounds

`MovementSelector` explicitly represents day offset and page, constructs `FDDA10080213DDPP`, and accepts only `DD=00/01`, `PP=00...07`. Day 0 is the capture local day; day 1 is the preceding local calendar day. The decoder uses calendar-day subtraction, not 86,400 seconds or a new timestamp correction. Minute offset remains `page × 180 + index`.

Only **0100 and 0107** were physically observed for day 1. Other `01PP` selectors can be constructed using the supported format but expose `physicallyObserved = false`; this is not a claim of radio validation. Offsets above 1 and page indices above 7 are rejected, with raw evidence retained. All current-day decoding and future/zero rules remain intact. Movement decoder version is now `x6-movement-v0.2`; metric decoder `x6-v0.3` is unchanged.

DEBUG diagnostics offers single-page 0100 and 0107 actions. Each sends exactly one request, waits at most eight seconds, and completes only for the matching device/day/page. It does not fan out to other previous-day pages or enter routine production sync. The existing current-day burst/fallback path remains intact. Diagnostics shows full selectors, so a missing 0107 is reported as 0107, not 0007. Same-numbered pages from another day cannot complete the request.

## Storage and schema

**Schema stays 3. No migration or new persisted field is required.** The existing movement record already stores represented local day/time, minute offset, page/index, raw byte, packet ID, timezone, decoder version and semantic evidence. Its identity remains device + represented day + minute offset; capture day is not used as the represented-day key.

The retained packet identified by `packetID` contains the exact DDPP prefix. `MinuteMovementSample.selector(from:)` exposes its day offset/page explicitly without duplicating persisted evidence or changing the schema. New semantic descriptions also identify the selector/day offset. Actual live TX records preserve requested selectors separately; the transcribed fixtures preserve reported requests in their manifest because no exact TX times were supplied.

Tests show current-day capture on 27 Sep and previous-day capture on 28 Sep deduplicate for the same represented minute, while 27 Sep and 28 Sep positions remain distinct. Raw packets remain stored across replay and schema-3 serialization round trips. Existing schema-3 archives load without rewriting or migration; replay understands the newly supported frames.

## Overnight page planner

`X6Research.MovementPagePlanner` is development-only and does not send BLE writes. Given a capture date/timezone and a half-open interval, it returns only intersecting pages in chronological order and rejects windows outside the current/previous-day range.

For **27 Sep 23:30 → 28 Sep 08:35**, captured on 28 Sep, the exact plan is:

```text
0107, 0000, 0001, 0002
```

Boundary tests exclude an irrelevant page when an interval ends exactly at 03:00. No 0100 or other unrelated page is needed for this overnight interval. Both new raw frames remain in the fixture, but alignment uses no 0100 positions and only the last 30 positions of 0107.

## Second-night coverage and statistics

The coverage gate passed: **515/545 → 545/545 observed movement minutes**, missing **30 → 0**. The 515 post-midnight rows are byte-identical before/after. Only 23:30–23:59 gains movement; no interpolation or stage copying into the production archive occurs.

Reference totals remain **545 in bed, 542 asleep, 3 awake; Core 273, REM 221, Deep 48**. All second-night positions are nonzero observed raw signal; there are no zero, future or missing positions inside this window.

| Stage | Movement minutes before → after | Min / max | Raw mean | Median | 0x80 count / fraction |
|---|---|---|---:|---:|---|
| Core | 254 → 273 | 128 / 162 | 129.590 | 128 | 226 / 0.8278 |
| REM | 213 → 221 | 128 / 164 | 129.697 | 128 | 184 / 0.8326 |
| Deep | 48 → 48 | 128 / 149 | 129.208 | 128 | 43 / 0.8958 |
| Awake | 0 → 3 | 128 / 128 | 128.000 | 128 | 3 / 1.0000 |

All three recovered Awake minutes are raw 0x80. Awake is now describable on the second night, but three minutes do not establish statistical separation and the values overlap the most common sleep value.

Stage-boundary coverage improves from **42/45 to 45/45**. Boundary absolute change mean becomes **2.444** (previously 2.619); within-stage mean becomes **2.854** (previously 2.911). Both medians remain zero. Full distributions are in `transitions.json`.

HR/SDNN observations, times, counts and stage associations are unchanged. They remain separately sourced sparse vendor-export observations: Core HR 4 points/69.75 bpm, REM 12/64.00, Deep 2/59.00; Core SDNN 4/12.00 ms, REM 12/12.083, Deep 2/12.50. Awake still has no HR/SDNN observations. No oxygen series was added.

Outputs: [summary](analysis/2026-09-28/summary.md), [CSV](analysis/2026-09-28/alignment.csv), [JSON](analysis/2026-09-28/alignment.json), [statistics](analysis/2026-09-28/statistics.json), [transitions](analysis/2026-09-28/transitions.json), [comparison](analysis/2026-09-28/cross-night-comparison.md).

## Updated cross-night conclusions

- Core/REM remain poorly separable by raw movement: means nearly coincide and medians are 128 on both nights. Their small mean ordering still reverses.
- Deep remains higher than Core/REM on 27 Sep but lower on 28 Sep. The direction is not stable.
- Awake’s missing-coverage limitation is resolved for the second night. Its three values are all 128, overlapping sleep; first-night Awake also has median 128, with 19 zero/uninterpreted minutes excluded. No useful validated separation follows.
- 0x80 remains common in every stage. Second-night Awake fraction is 1.0, while Deep’s frequency ordering reverses between nights. No stage code is established.
- Boundary-change means remain higher than within-stage changes on 27 Sep and lower on 28 Sep. The added boundaries do not establish a stable movement-spike association.
- HR/SDNN conclusions do not change because those observations did not change: overlapping distributions, sparse stage coverage and insufficient evidence for useful stage discrimination.

**Insufficient evidence for production sleep staging.** No threshold classifier, HMM, ML model, sleep score, or production HealthKit source was added. Product copy remains “Awaiting protocol/model validation”.

## Validation

- `swift test`: **50 tests passed, zero failures**, including seven new test cases with multiple selector, coverage, preservation and planning assertions.
- Generic iOS Simulator build: **succeeded**.
- Existing iPhone 17 Pro simulator UI suite: **4 tests passed, zero failures**.
- Both nightly analyses and the cross-night comparison: **byte-identical across repeated runs**.
- First-night outputs (including the export-enhanced rerun): unchanged bytes.
- Historical validation reports: unchanged hashes. Only the explicitly requested second-night analysis artifacts were updated.
- `git diff --check`: passed.

The previous unsupported-offset test now rejects **day 2** instead of day 1, because day 1 is the newly supported behavior; rejection coverage is preserved. New tests independently cover actual 0100/0107 mapping, last-30-minute mapping, deduplication, distinct day identities, wrong-day response rejection, bounded one-page requests, unsupported offsets, narrow planning, DST calendar-day subtraction, schema-3 round trip, 545/545 coverage, unchanged post-midnight rows, deterministic output and absence of production sleep samples.

Local logs/results: `/private/tmp/vitaepoch-previous-day-20260928/`, including `ui-tests.xcresult`. The checked physical bytes came from the supplied nRF evidence; no new installation or radio request was performed during this implementation.

## Not yet validated

Every middle previous-day page (0101–0106), offsets above 1, retention depth over time, exact movement amplitude meaning, and production sleep staging. The existing unresolved `020F`, `0211`, `0212`, stress timestamp and provisional wrist-temperature semantics are unchanged.

## Needs another physical X6 validation

1. Use the new VitaEpoch DEBUG 0100/0107 actions and verify actual returned dates, matching-selector completion, diagnostics, and same-day deduplication after reconnect/relaunch.
2. If collection expands to 0101–0106, validate those individual selectors on the X6 before calling that entire previous-day family physically verified.

## Exact changed-file list

- `README.md` — Documents previous-day evidence and the exact full-coverage analysis invocation.
- `Sources/VitaEpochCore/MovementHistory.swift` — Adds bounded explicit selectors, prior local-day decoding and packet-derived selector access without schema changes.
- `Sources/VitaEpochCore/SyncDiagnostics.swift` — Tracks one selected movement day/page with exact selector diagnostics and bounded acquisition.
- `Sources/X6Research/MovementPagePlanner.swift` — Plans only intersecting current/previous-day pages for a research interval.
- `Sources/X6SleepAnalysis/main.swift` — Accepts a separate raw movement-evidence archive for offline replay.
- `Tests/VitaEpochCoreTests/Fixtures/physical-2026-09-28-previous-day/README.md` — Distinguishes physical transcription, approximate time anchor, mapping and limits.
- `Tests/VitaEpochCoreTests/Fixtures/physical-2026-09-28-previous-day/capture.json` — Stores the two exact frames with source/profile provenance.
- `Tests/VitaEpochCoreTests/Fixtures/physical-2026-09-28-previous-day/frames-verbatim.txt` — Preserves the exact supplied 0100 and 0107 text lines.
- `Tests/VitaEpochCoreTests/Fixtures/physical-2026-09-28-previous-day/manifest.json` — Records source/frame hashes, requests, date, profile and unvalidated extrapolations.
- `Tests/VitaEpochCoreTests/PhysicalEvidenceTests.swift` — Updates the unsupported-offset assertion from newly supported 1 to unsupported 2.
- `Tests/VitaEpochCoreTests/PreviousDayMovementTests.swift` — Adds seven tests for exact physical decoding, date identity, requests, planning, DST, full coverage and determinism.
- `VitaEpoch/BLE/X6CentralManager.swift` — Adds a DEBUG previous-day single-page acquisition helper.
- `VitaEpoch/UI/DeviceView.swift` — Adds 0100/0107 diagnostic actions and full DDPP response labels.
- `docs/X6_PREVIOUS_DAY_MOVEMENT_2026-09-28.md` — Records this evidence pass, exact changes, updated statistics and remaining radio checks.
- `docs/analysis/2026-09-28/alignment.csv` — Fills only the missing 30 movement rows.
- `docs/analysis/2026-09-28/alignment.json` — Adds the same 30 raw values and linked packet IDs.
- `docs/analysis/2026-09-28/cross-night-comparison.json` — Updates the corresponding machine-readable comparison.
- `docs/analysis/2026-09-28/cross-night-comparison.md` — Reassesses Awake, byte frequencies and movement boundaries.
- `docs/analysis/2026-09-28/statistics.json` — Recomputes full-window stage statistics.
- `docs/analysis/2026-09-28/summary.md` — Updates complete coverage and stage/boundary statistics.
- `docs/analysis/2026-09-28/transitions.json` — Includes all 45 second-night stage boundaries.
- `scripts/compare_sleep_nights.py` — Handles newly observed Awake coverage and regenerates its descriptive comparison.

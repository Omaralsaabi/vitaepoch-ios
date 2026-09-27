# X6 correctness / stability pass — 26 September 2026

No Age, Recovery, HealthKit, or new product feature work was performed. The existing Age screen only received the requested pluralization and sleep copy corrections.

## Evidence and exact incomplete requests

The app's original archive was copied **read-only** from the paired iPhone. It contains 35 packets and 16 decoded samples across two syncs. The source on the iPhone was not changed or deleted. The regression fixture preserves the bytes and times, with only the peripheral UUID anonymized.

| Request | Written command | Captured response sequence, in each sync | Previously incomplete because |
|---|---|---|---|
| 020F — periodic HR | `FDDA1007020F00` | one 152-byte page `0000`, all values zero | page `0001` never arrived |
| 0210 — vendor HRV | `FDDA100802100000` | one 152-byte page `0000`, all values zero | pages `0001`, `0002`, `0003` never arrived |
| 0216 — wrist temperature | `FDDA100802160000` | one 152-byte page `0000`, all values zero | pages `0001`, `0002`, `0003` never arrived |

Manual HR, SpO₂, stress, and activity each received a valid response. All observed full history frames are well formed and the existing assembler accepts them. The captured zeros were not evidence of a parser discarding nonzero data: later pages are absent from the raw archive itself.

Developer diagnostics now retain each request's exact feature, TX bytes and page/variant, ordered RX prefixes, byte counts, decoded sample counts, elapsed times, and completion/timeout/interruption reason. Valid empty pages count toward completion independently of decoded samples. New live requests have actual start/end timestamps. Historical replay labels inferred boundaries explicitly; original timer firings were never logged, so the final request's elapsed time is unavailable rather than fabricated.

For 0210/0216 the driver allows automatic notification bursts first, then requests missing `00/page` variants once each after a quiet interval. This page-selector read strategy is **provisional and needs physical validation**; only `0000` TX exists in the captured evidence. 020F's one-byte selector is not extrapolated into an undocumented continuation command. If its second page still does not arrive, it remains explicitly incomplete.

## Timestamp audit

| Record family | Time rule in this pass |
|---|---|
| Manual 0209 | Preserve little-endian raw seconds/bytes; use the confirmed device/capture-day reference when identity and exact captured HR history match. |
| Manual 020B / 0219 | Same captured-device/day adjustment, explicitly marked **shared-reference provisional** pending exact Da Halo times. |
| Live 2A37 | Notification receipt instant; no manual correction. |
| Periodic 020F / 0210 / 0216 | Receipt timezone + day offset + page/slot wall-clock grid; no manual correction. Layout/time interpretation stays provisional; nonexistent DST clock slots are not shifted into other slots. |
| Activity 020D / FDD1 | Local day snapshots; no manual correction. Day/index interpretation stays provisional. |

`D274B76A` = 1790407890. Old interpretation: 07:31:30 UTC → **10:31:30 Amman**. Confirmed reference: **15:31:30 Amman / 12:31:30 UTC**, preserving the captured seconds. The +18,000-second adjustment is limited to the matched device, known firmware/serial, and encoded capture date (26 September). It is not a universal timezone fix and does not silently affect other devices or future days. Outside that evidence scope, manual timestamps remain explicitly unverified.

Every new decoded sample retains its timestamp basis, raw seconds/bytes where applicable, page/day/slot where applicable, timezone, adjustment, reference ID, and decoder version. New packets retain their receipt timezone. Old packets without receipt timezone use the matched capture reference when available, otherwise the current calendar; that reconstruction remains provisional.

Migration makes an exact `archive.before-v2.json` backup before writing anything, keeps every raw packet, and preserves prior decoded records in `previousDecodes`. It replays the raw archive into v0.2 records without duplicating the corrected measurements. Unknown/undecodable raw evidence remains intact.

## HRV and temperature outcome

- **Actual captured archive:** still no HRV or wrist-temperature readings; it contains only zero pages. No readings are fabricated.
- **Constructed four-page fixtures:** HRV `11, 14, 12, 13, 10 ms` and temperature `36.3, 36.2, 36.4 °C` survive assembly, empty/duplicate/out-of-order pages, archive handling, queries, and populated UI tests.
- Full nonzero captured sequences and exact SpO₂/stress reference times are pending from the user. HRV remains vendor HRV with its statistic unverified. Temperature remains **Wrist Temperature**, with provisional metadata.

## Stability and UI

- `ArchiveWorker` handles parsing, migration, JSON I/O, and chart preparation off MainActor. Writes debounce for 350 ms, with a 2-second maximum delay; sync end, disconnect, and scene changes flush. UI snapshots coalesce separately.
- First run creates Application Support and returns an empty archive without opening a nonexistent file. Corrupt archives are not overwritten. This removes that app-side failure path. Simulator unified logs still show two `fopen errno=2` messages emitted by `libCoreFSCache.dylib` during the populated chart test; they come from a framework cache component, not a logged archive-open failure. The exact cache path is not supplied, so no cache deletion/workaround was attempted.
- Day is an intraday series; Week and longer ranges use daily medians for physiological metrics and the latest daily activity snapshot. Missing days remain gaps. Axes explicitly use hours for Day and dates for Week. Segmented state resets chart selection.
- Native TabView and NavigationStack remain. Pages reserve bottom safe-area spacing, and metric details hide the tab bar. Native toolbar back navigation is exercised in UI tests; no custom circular back control exists in this repository.
- Charts have a fixed positive height, skip construction during zero-width/height layout passes, and use nondegenerate domains. No custom image renderer exists. The original `1125x0 image slot` message cannot be conclusively attributed to a specific framework surface without a stack trace. No matching message appeared in the simulator app logs for these tests.
- `radiowaves.left.and.right` was replaced with `antenna.radiowaves.left.and.right`.
- Main-thread decode/file work was a credible contributor to gesture stalls and has been removed. No matching gesture-gate message appeared in these simulator test logs. Simulator checks do not prove that the physical-device gesture timeout is resolved.

## Validation

- `swift test`: 21 tests passing, covering original fixtures plus timestamp calibration, scoped correction, page handling, legacy sync reconstruction, chart aggregation/DST boundaries, first-run archive behavior, batched writes, backup/migration, and corrupt-file preservation.
- Simulator build: passing with Swift 6.
- Simulator UI tests: **3 passing**; cases cover empty navigation, captured Day/Week behavior/native back/safe area, and constructed HRV/temperature rendering.
- Physical X6 revalidation: **not performed**. No new app build was installed or BLE command sent to the physical band in this pass.

## Every changed file

| File | Change |
|---|---|
| `Package.swift` | Includes captured test resources. |
| `Sources/VitaEpochCore/Domain.swift` | Adds timestamp evidence and receipt timezone; decoder version v0.2. |
| `Sources/VitaEpochCore/TimestampEvidence.swift` | Defines raw time provenance and the scoped captured-device reference. |
| `Sources/VitaEpochCore/X6Protocol.swift` | Records raw/slot timestamp evidence and accepts explicit empty page headers. |
| `Sources/VitaEpochCore/LocalArchive.swift` | Adds migration/diagnostic fields and guarded first-run directory creation. |
| `Sources/VitaEpochCore/PacketProcessor.swift` | Centralizes assembly, decode, evidence-preserving replay, and reference application. |
| `Sources/VitaEpochCore/SyncDiagnostics.swift` | Tracks writes, ordered replies, empty-page completion, missing variants, and reasons. |
| `Sources/VitaEpochCore/LegacySyncAudit.swift` | Reconstructs old sync failures with explicit limits on inferred timing. |
| `Sources/VitaEpochCore/ArchiveWorker.swift` | Actor-based parsing/storage, backup migration, batched writes, and flushes. |
| `Sources/VitaEpochCore/MetricQueries.swift` | Pure Day/Week queries and background-prepared display snapshots. |
| `VitaEpoch/Storage/AppStore.swift` | Ordered actor calls and coalesced UI publication replace synchronous file work. |
| `VitaEpoch/BLE/X6CentralManager.swift` | Uses background ingestion, per-request diagnostics, page handling, and session guards. |
| `VitaEpoch/UI/Components.swift` | Safe-area spacing, guarded chart sizing, explicit axes, and daily-summary rendering. |
| `VitaEpoch/UI/MetricDetailView.swift` | Typed range state, timestamp confidence copy, daily/intraday queries, native detail navigation. |
| `VitaEpoch/UI/DeviceView.swift` | Valid antenna symbol and detailed sync/timestamp diagnostics. |
| `VitaEpoch/UI/RootTabView.swift` | Requested singular/plural and sleep wording fixes; metric test identifiers. |
| `VitaEpoch/VitaEpochApp.swift` | Scene flushes and isolated debug-only UI fixture loading. |
| `Tests/VitaEpochCoreTests/StabilityTests.swift` | Captured timestamp/sync audit and constructed page/chart regression tests. |
| `Tests/VitaEpochCoreTests/ArchiveWorkerTests.swift` | First-run, batching, lossless migration, and corrupt-archive tests. |
| `Tests/VitaEpochCoreTests/Fixtures/device-2026-09-26.json` | Actual captured regression archive, peripheral UUID anonymized. |
| `Tests/VitaEpochCoreTests/Fixtures/README.md` | Distinguishes captured evidence from constructed test cases. |
| `UITests/VitaEpochUITests.swift` | Isolated empty/populated navigation, range, layout, and history rendering checks. |
| `scripts/generate_project.py` | Adds UI fixture resources and preserves owner signing/bundle settings when regenerating. |
| `VitaEpoch.xcodeproj/project.pbxproj` | Registers new source files/resources; preserves the existing app bundle ID/team. |
| `README.md` | Updates storage/testing status and links this report. |
| `docs/STABILITY_VALIDATION.md` | Records findings, limitations, validation, and this file-by-file summary. |

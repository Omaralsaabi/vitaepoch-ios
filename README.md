# VitaEpoch

A native, local-first SwiftUI companion for the X6 / MOYOUNG band. This is the first device-validation build, targeting iOS 17+ with Swift 6.

## Run

Open `VitaEpoch.xcodeproj`, select the **VitaEpoch** scheme, and run on an iPhone or simulator. For an iPhone, choose your development team and replace the `com.example.vitaepoch` bundle identifier under Signing & Capabilities.

The simulator supports UI testing; X6 pairing requires a physical iPhone. In **Device**, tap **Find my band**, then select your X6. Permission is requested only when you begin connecting. Disconnect the band from Da Halo if it is unavailable.

## Implemented

- Today, Trends, Age, and Device tabs, native charts, metric details, and light/dark appearances.
- X6 discovery, connection, bounded reconnect attempts, notifications, battery/device information, and one-shot heart rate controls.
- Confirmed history commands, paced by responses with page tracking and timeout reporting.
- Parsers for manual HR, SpO₂, stress, daily/compact activity, periodic HR, vendor HRV, wrist temperature, and standard BLE heart rate.
- Fragment/coalesced-frame handling and development raw TX/RX logs.
- Atomic local persistence, record deduplication, source/device identity, decoder version, packet evidence, and provisional-layout labels.
- Honest empty states and an Age baseline-progress screen. No fabricated health scores or demo measurements appear in production screens.

## Validation

```sh
swift test
xcodebuild -project VitaEpoch.xcodeproj -scheme VitaEpoch \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project VitaEpoch.xcodeproj -scheme VitaEpoch \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO test
```

Core tests run independently of UIKit and Bluetooth. The Xcode test action runs isolated empty-state and populated fixture tests for navigation, chart ranges, safe areas, and history rendering. `scripts/generate_project.py` regenerates project references after adding Swift files; it requires only Python's standard library.

## Architecture

- `Sources/VitaEpochCore`: pure Swift protocol, commands, domain records, and archive format. Built by both Swift Package Manager and the app target.
- `VitaEpoch/BLE`: CoreBluetooth lifecycle, safe command list, response routing, and sync.
- `VitaEpoch/Storage`: observable local archive adapter and display queries.
- `VitaEpoch/UI`: reusable SwiftUI components, screens, and Swift Charts.
- `Tests`: confirmed fixture tests plus explicitly synthetic paging/transport cases.
- `UITests`: first-run navigation checks.

The app stores an atomic JSON archive in Application Support. Parsing, query preparation, migration, and batched writes run on a background actor. Raw evidence has no retention cutoff; migration makes an exact backup and retains prior decodes. Indexed SQLite/SwiftData remains a future storage optimization for extended use.

See [the correctness/stability report](docs/STABILITY_VALIDATION.md) for the real-device archive findings, capture-scoped timestamp correction, precise incomplete requests, fixture provenance, and remaining physical-validation requirements.

## Next milestones

1. Validate on an actual X6: notification sequencing, time-zone/day mapping, paged replies, disconnects, and one-shot measurement behavior. The packet fixtures have been tested; radio behavior has not.
2. Inspect Pulse's current engines and license/NOTICE before adapting baseline, recovery, and age-model components. No upstream code has been copied yet.
3. Add optional read-only HealthKit, explicit source resolution, profile onboarding, validated baseline/completeness rules, and a versioned calibrated age model.
4. Add temperature-baseline deviation, age/contributor trends, accessible chart refinement, diagnostics export, and long-term storage.
5. Decode sleep only from real captures. Keep raw PPG investigation separate until waveform access is established.

The current Age screen counts days containing heart data, **not validated complete days**. An age number stays unavailable even after seven days until the model and input gates exist. The later 7/14/30-day requirements take precedence over the older three-day onboarding example.

## Protocol boundaries

X6 HRV is not assumed to be RMSSD. Sparse HR buckets are not observed maximum HR. Temperature is wrist temperature. Unknown features are saved without interpretation; FDD5 and unknown writes are never used. Day offsets and several layouts remain provisional as documented in the handoff. No time-setting command is sent, so an incorrect band clock must be corrected externally.

## Physical evidence and offline sleep research

The [27 Sep integration report](docs/X6_PHYSICAL_EVIDENCE_2026-09-27.md) records scoped SDNN semantics, independently confirmed SpO₂ timestamps, raw `0213` minute positions, fixture limitations, and physical revalidation requirements. The two previous validation reports remain historical evidence.

Run the development-only alignment utility with an archive and vendor reference intervals:

```sh
swift run x6-sleep-analysis \
  Tests/VitaEpochCoreTests/Fixtures/physical-2026-09-27/capture.json \
  Tests/VitaEpochCoreTests/Fixtures/physical-2026-09-27/sleep-reference.json \
  docs/analysis/2026-09-27
```

It writes CSV, JSON, and Markdown descriptive statistics, preserving sparse data without interpolation or stage inference. Optional arguments are a JSON array of explicitly annotated `0211` candidates and a device ID. `Sources/X6Research` and `Sources/X6SleepAnalysis` are Swift package tooling only; they are not linked into the iOS app. See the [fixture provenance](Tests/VitaEpochCoreTests/Fixtures/physical-2026-09-27/README.md) before interpreting the output.

The [28 Sep revalidation report](docs/X6_PHYSICAL_REVALIDATION_2026-09-28.md) adds bounded, missing-page-only movement fallback after the automatic-burst window. Archive schema remains 3. Reported HRV/temperature continuation is physically validated for the matched X6; the new movement fallback still requires a run in VitaEpoch.

For offline vendor references, extract only Da Halo sleep and corresponding HR/SDNN/oxygen observations for the requested night:

```sh
python3 scripts/extract_sleep_reference.py '/path/to/export 28 sep.zip' 2026-09-28 /path/to/research-inputs
swift run x6-sleep-analysis \
  Tests/VitaEpochCoreTests/Fixtures/physical-2026-09-28/capture.json \
  /path/to/research-inputs/sleep-reference.json /path/to/research-output \
  --vendor-observations /path/to/research-inputs/vendor-observations.json
```

Vendor observations occupy separate columns and retain source/record/interval provenance; they never become packet-decoded records or app sleep results. The [two-night comparison](docs/analysis/2026-09-28/cross-night-comparison.md) preserves the missing pre-midnight window and supports no production classifier. `scripts/compare_sleep_nights.py` regenerates that specific 27/28 Sep comparison from the two analysis directories; its narrative is scoped to those nights.

The [previous-day movement report](docs/X6_PREVIOUS_DAY_MOVEMENT_2026-09-28.md) documents the observed `0100` and `0107` selectors. The decoder accepts only day offsets 0 and 1. DEBUG diagnostics can request either observed previous-day page without starting a full prior-day sync. The research page planner selects only pages intersecting a requested window.

To reproduce the second night with all 545 movement minutes, preserve the current-day and previous-day evidence as separate input archives:

```sh
swift run x6-sleep-analysis \
  Tests/VitaEpochCoreTests/Fixtures/physical-2026-09-28/capture.json \
  docs/analysis/2026-09-28/sleep-reference.json docs/analysis/2026-09-28 \
  --vendor-observations docs/analysis/2026-09-28/vendor-observations.json \
  --movement-evidence Tests/VitaEpochCoreTests/Fixtures/physical-2026-09-28-previous-day/capture.json
python3 scripts/compare_sleep_nights.py \
  docs/analysis/2026-09-28/comparison-2026-09-27 \
  docs/analysis/2026-09-28 docs/analysis/2026-09-28
```

Schema remains 3: represented local day and packet evidence already preserve movement identity and the raw DDPP selector. Full movement coverage does not establish a production sleep algorithm.

## Sleep Detection V0 benchmark

The [V0 research report](docs/SLEEP_DETECTION_V0_2026-09-28.md) evaluates whole-night Sleep/Awake agreement with the vendor reference. Results are inconsistent across directions and negative controls; they do not justify a production classifier. All [benchmark artifacts](docs/analysis/sleep-detection-v0/summary.md) are isolated from the app.

The runner requires local Python 3.11, NumPy, SciPy and scikit-learn (recorded run: 2.3.5, 1.16.3, 1.8.0 respectively), plus Swift. It performs no installation or network access. Use a Python environment containing those research dependencies:

```sh
python3 -B -m unittest discover -s scripts -p 'test_sleep_detection_v0.py' -v
python3 -B scripts/sleep_detection_v0.py
python3 -B scripts/sleep_detection_v0.py --output /tmp/vitaepoch-sleep-v0-repeat
diff -qr docs/analysis/sleep-detection-v0 /tmp/vitaepoch-sleep-v0-repeat
```

The runner replays existing fixtures in temporary directories, checks equality with authoritative alignments, and derives causal features using captured unlabeled context. `x6-sleep-analysis --export-movement-context` enables that optional context export; ordinary alignment output is unchanged. Raw zeros/missingness remain evidence, HR/SDNN remain exact sparse vendor observations, and no app sleep samples are created. Dependency versions are part of the manifest, so byte reproducibility assumes the recorded environment.

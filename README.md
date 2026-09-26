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

Core tests run independently of UIKit and Bluetooth. The Xcode test action runs a UI navigation/empty-state test. `scripts/generate_project.py` regenerates project references after adding Swift files; it requires only Python's standard library.

## Architecture

- `Sources/VitaEpochCore`: pure Swift protocol, commands, domain records, and archive format. Built by both Swift Package Manager and the app target.
- `VitaEpoch/BLE`: CoreBluetooth lifecycle, safe command list, response routing, and sync.
- `VitaEpoch/Storage`: observable local archive adapter and display queries.
- `VitaEpoch/UI`: reusable SwiftUI components, screens, and Swift Charts.
- `Tests`: confirmed fixture tests plus explicitly synthetic paging/transport cases.
- `UITests`: first-run navigation checks.

The first build stores an atomic JSON archive in Application Support. It preserves all raw evidence without a retention cutoff. Before extended daily use, replace this adapter with indexed SQLite/SwiftData and batched background writes; the current whole-file writes are intended for initial device validation.

## Next milestones

1. Validate on an actual X6: notification sequencing, time-zone/day mapping, paged replies, disconnects, and one-shot measurement behavior. The packet fixtures have been tested; radio behavior has not.
2. Inspect Pulse's current engines and license/NOTICE before adapting baseline, recovery, and age-model components. No upstream code has been copied yet.
3. Add optional read-only HealthKit, explicit source resolution, profile onboarding, validated baseline/completeness rules, and a versioned calibrated age model.
4. Add temperature-baseline deviation, age/contributor trends, accessible chart refinement, diagnostics export, and long-term storage.
5. Decode sleep only from real captures. Keep raw PPG investigation separate until waveform access is established.

The current Age screen counts days containing heart data, **not validated complete days**. An age number stays unavailable even after seven days until the model and input gates exist. The later 7/14/30-day requirements take precedence over the older three-day onboarding example.

## Protocol boundaries

X6 HRV is not assumed to be RMSSD. Sparse HR buckets are not observed maximum HR. Temperature is wrist temperature. Unknown features are saved without interpretation; FDD5 and unknown writes are never used. Day offsets and several layouts remain provisional as documented in the handoff. No time-setting command is sent, so an incorrect band clock must be corrected externally.

# App icon validation — 28 Sep 2026

## Causes and corrections

| App Store Connect error | Root cause | Correction |
|---|---|---|
| 90022: missing iPhone 120×120 icon | No asset catalog existed; app resource phase was empty. | Added AppIcon iPhone slots, including 60pt @2x, producing an opaque 120×120 icon. |
| 90023: missing iPad 152×152 icon | The target advertises Universal support (`TARGETED_DEVICE_FAMILY = "1,2"`) but had no iPad icons. | Retained iPad support and added all required slots, including 76pt @2x. |
| 90713: missing CFBundleIconName | No selected AppIcon set or compiled asset-catalog metadata was merged into the generated Info.plist. | Selected AppIcon in Debug/Release and registered Assets.xcassets in the target resource phase. Xcode now emits the primary icon name for both device families. |

Deployment target remains iOS 17.0. Existing bundle identifier, signing team, version, and device support remain unchanged. No manual Info.plist or manually authored legacy CFBundleIconFiles array was added. The generator remains the project source of truth.

## Artwork and configuration

Source: existing user-supplied `app_icon.png`, 1254×1254, opaque. SHA-256: `eb9626c49bd006f0069670f46ca2ab63becb058605b62c47f2f9076fd841eb2e`. The source is unchanged. `scripts/generate_app_icon.py` uses macOS sips to resize it without cropping, adding a mask, or altering the design.

One catalog: `VitaEpoch/Assets.xcassets`, with one `AppIcon.appiconset`. The Xcode Contents.json schema has 18 slots backed by 13 distinct RGB PNG dimensions:

- iPhone: 20pt, 29pt, 40pt and 60pt, each @2x/@3x.
- iPad: 20pt, 29pt, 40pt and 76pt @1x/@2x; 83.5pt @2x.
- iOS marketing: 1024pt @1x.

All PNG headers and slot dimensions were checked; every source asset is RGB with no alpha channel. Shared pixel dimensions reuse the same PNG within this single appiconset.

Both Debug and Release have `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon` and `INFOPLIST_KEY_CFBundleIconName = AppIcon`, alongside the existing generated-Info.plist setting. The compiled product is authoritative: Xcode emits CFBundleIconName in the standard nested primary-icon dictionaries, not as a standalone top-level entry:

```text
CFBundleIcons.CFBundlePrimaryIcon.CFBundleIconName = AppIcon
CFBundleIcons~ipad.CFBundlePrimaryIcon.CFBundleIconName = AppIcon
UIDeviceFamily = [1, 2]
```

The CFBundleIconFiles entries in those dictionaries are emitted by actool, not conflicting hand-written configuration.

## Validation

- `swift test`: 43 passed, zero failures.
- Existing iPhone 17 Pro simulator UI suite: 4 passed, zero failures.
- `xcodebuild -project VitaEpoch.xcodeproj -scheme VitaEpoch -configuration Release -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`: succeeded.
- Same configuration with `archive` and an explicit archive path: succeeded.
- Project generator rerun: byte-identical project, with icon settings retained.
- `plutil`/plist parsing of the Release built app and archive: verified both primary-icon names and device families.
- `assetutil --info` on the archived Assets.car: verified opaque AppIcon renditions for iPhone 120×120, iPad 152×152 and marketing 1024×1024, plus the remaining slots.
- Archived `AppIcon60x60@2x.png` and `AppIcon76x76@2x~ipad.png`: verified 120×120 and 152×152, no alpha.
- `git diff --check`: passed.

Artifacts and logs: `/private/tmp/vitaepoch-appicon-validation/`. The inspected Release archive is `VitaEpoch.xcarchive` there. It is **unsigned**, intentionally built with CODE_SIGNING_ALLOWED=NO; it is not an upload-ready distribution archive. No App Store Connect upload or server-side validation was performed.

## Upload next step

Create a **new signed Release Archive** in Xcode and use Validate App / Distribute App for TestFlight. An old archive retains the missing icon configuration and cannot be fixed by changing the source project afterward. Increment the build number if App Store Connect requires a new one; this pass preserves the existing version/build settings.

## Exact files changed or added

The pre-existing `app_icon.png` is an unchanged input, not a file modified by this pass.

- `VitaEpoch/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png`
- `VitaEpoch/Assets.xcassets/AppIcon.appiconset/AppIcon-120.png`
- `VitaEpoch/Assets.xcassets/AppIcon.appiconset/AppIcon-152.png`
- `VitaEpoch/Assets.xcassets/AppIcon.appiconset/AppIcon-167.png`
- `VitaEpoch/Assets.xcassets/AppIcon.appiconset/AppIcon-180.png`
- `VitaEpoch/Assets.xcassets/AppIcon.appiconset/AppIcon-20.png`
- `VitaEpoch/Assets.xcassets/AppIcon.appiconset/AppIcon-29.png`
- `VitaEpoch/Assets.xcassets/AppIcon.appiconset/AppIcon-40.png`
- `VitaEpoch/Assets.xcassets/AppIcon.appiconset/AppIcon-58.png`
- `VitaEpoch/Assets.xcassets/AppIcon.appiconset/AppIcon-60.png`
- `VitaEpoch/Assets.xcassets/AppIcon.appiconset/AppIcon-76.png`
- `VitaEpoch/Assets.xcassets/AppIcon.appiconset/AppIcon-80.png`
- `VitaEpoch/Assets.xcassets/AppIcon.appiconset/AppIcon-87.png`
- `VitaEpoch/Assets.xcassets/AppIcon.appiconset/Contents.json`
- `VitaEpoch/Assets.xcassets/Contents.json`
- `VitaEpoch.xcodeproj/project.pbxproj`
- `docs/APP_ICON_VALIDATION.md`
- `scripts/generate_app_icon.py`
- `scripts/generate_project.py`

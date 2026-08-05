# P2PFileDemo

`P2PFileDemo` is the Apple-side sample app for this repository. It wraps `P2PFileSharingSDK` in a simple SwiftUI shell so we can test discovery, pairing, manifest browsing, and file downloads against a compatible Windows host.

## Purpose

- Demonstrate how an Apple app can embed `P2PFileSharingSDK`.
- Exercise the real local-network pairing and transfer flow end to end.
- Provide a thin demo UI for trusted-device management and remote file browsing.

## Important Constraint

`P2PFileDemo` is not a standalone sender or server. It needs a second device on the same local network that is acting as the host.

Today that host is expected to be a Windows machine running the companion runtime from this repo.

## Required Companion Host

For live local-network testing, you need all of the following:

- A second device running Windows on the same LAN as the Apple device or simulator.
- The Windows host runtime advertising `_p2pfiles._tcp`.
- A pairing payload from the Windows side so the Apple app can trust that host.

The easiest setup is:

1. Start `Windows/P2PFile.Tray`.
2. Choose or confirm the Windows share root.
3. Let the tray self-host the runtime, or let it attach to an already running `P2PFile.Service`.
4. Use the tray-provided QR code or copied payload string when pairing from `P2PFileDemo`.

`P2PFile.Service` can keep the host runtime running in the background, but `P2PFile.Tray` is still the practical companion app for first-time pairing because it exposes the QR code, payload, and host status UI.

## Typical Demo Flow

1. Launch `P2PFileDemo` on the Apple side.
2. Tap `Pair New Device`.
3. Scan the QR code from the Windows tray, or paste the manual payload if camera scanning is unavailable.
4. Select the newly trusted PC to reconnect and load its manifest.
5. Download files into the demo app's destination folder.

## Simulator And Device Notes

- The iOS simulator can browse and pair, but camera scanning may not be available. Use the manual payload field when needed.
- On a real iPhone or iPad, the app can use the camera scanner for QR-based pairing.
- The demo currently targets iOS 17 or later.

## Storage Behavior

By default, downloaded files are stored in the app's local documents area. If you add the right iCloud entitlements and container configuration, the demo can also target an app-owned iCloud Drive location.

## Build

Open `Apple/P2PFileDemo/P2PFileDemo.xcodeproj` in Xcode and build the `P2PFileDemo` scheme.

Example:

```bash
xcodebuild -project 'Apple/P2PFileDemo/P2PFileDemo.xcodeproj' \
  -scheme P2PFileDemo \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  build CODE_SIGNING_ALLOWED=NO
```

## Verification Notes

- The Apple package now has standalone `swift test` coverage for pairing payloads, manifest comparison, path normalization, trusted-device coding, protocol framing, malformed frame rejection, saved-file reconciliation, and partial-file cleanup.
- The simulator build is verified.
- Real iPad to real Windows transfer validation is verified on native hardware.

## Related Files

- [`P2PFileSharingSDK`](./P2PFileSharingDemoSDK/README.md)
- [`../../Windows/README.md`](../../Windows/README.md)
- [`../../docs/architecture.md`](../../docs/architecture.md)

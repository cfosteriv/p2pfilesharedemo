# P2PFileSharingSDK

`P2PFileSharingSDK` provides the P2P local-network file-sharing client stack for discovering nearby devices, pairing with them, comparing manifests, and downloading files into app-controlled destinations.

## What it includes

- `P2PFileSharingBrowserController` as the main observable client controller.
- `P2PFileSharingBrowserView` and related SwiftUI pairing/browser views.
- `P2PFileSharingConfiguration` for Bonjour service and QR scheme normalization.
- Bonjour discovery and TCP transport implementations.
- Stores for trusted devices, transfer records, and local identity.
- Destination resolvers for local app folders and iCloud ubiquitous containers.

## When to use it

Use this target when an Apple app needs to browse a compatible P2P file-sharing host, pair with nearby devices, and import files into app-managed storage.

## Quick start

```swift
import P2PFileSharingSDK
import UIKit

let controller = P2PFileSharingBrowserController(
    localDisplayName: UIDevice.current.name,
    trustedStore: KeychainPairedDeviceStore(),
    identityProvider: LocalDeviceIdentityStore(),
    transferRecordStore: JSONTransferRecordStore(fileURL: recordsURL),
    destinationResolver: AppleDownloadDestinationResolver(
        applicationFolderName: "MyApp",
        importedFolderName: "Imported Files"
    ),
    configuration: .default
)

Task {
    await controller.handleAppDidBecomeActive()
}
```

## Configuration requirements

The host app must still own the Apple-side local network configuration. At minimum, add these entries to `Info.plist`:

```xml
<key>NSLocalNetworkUsageDescription</key>
<string>This app uses your local network to discover and connect to nearby devices.</string>
<key>NSBonjourServices</key>
<array>
    <string>_p2pfiles._tcp</string>
</array>
```

If you customize `P2PFileSharingConfiguration(serviceType:)`, the `NSBonjourServices` entry must match the normalized service type exactly.

The SDK fails early with a descriptive message if required local-network configuration is missing.

## Configuration behavior

`P2PFileSharingConfiguration` normalizes:

- service types such as `warehousefiles._TCP.local` into `_warehousefiles._tcp`,
- domains such as `local` into `local.`,
- QR schemes such as `WarehouseFiles://pair` into `warehousefiles`.

Defaults:

- service type: `_p2pfiles._tcp`
- domain: `local.`
- QR code scheme: `p2pfiles`

## Storage and persistence choices

The SDK is intentionally modular. The host app chooses how to persist and route data:

- `KeychainPairedDeviceStore` or `MemoryPairedDeviceStore` for trusted devices,
- `JSONTransferRecordStore` or `MemoryTransferRecordStore` for transfer history,
- `LocalDeviceIdentityStore` for device identity,
- `AppleDownloadDestinationResolver` or `UbiquitousContainerDestinationResolver` for imported file locations.

If you use `UbiquitousContainerDestinationResolver`, the host app must already have working iCloud container entitlements.

## UI and controller flow

`P2PFileSharingBrowserController` handles:

- discovery refresh when the app becomes active,
- pairing from QR payloads,
- reconnecting to trusted devices,
- manifest comparison through `ManifestComparator`,
- selection and transfer state for remote files.

## Testing

Run package tests from this folder:

```bash
swift test
```

Current Swift package coverage includes:

- pairing payload validation and QR parsing,
- manifest comparison,
- path normalization,
- fingerprint normalization,
- trusted-device JSON encoding/decoding,
- frame encoding/decoding and malformed-frame rejection,
- saved-file reconciliation,
- partial-file cleanup on cancelled or failed transfers.

## Related targets

- This target is independent from Firebase.
- The `P2PFileDemo` sample app and its tests reference this package locally through the Xcode project.

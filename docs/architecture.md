# Architecture

## Overview

The reference system is split into one shared protocol and two platform implementations:

- Apple uses `P2PFileSharingSDK` plus a SwiftUI demo app.
- Windows uses `P2PFile.Runtime` plus service and tray shells, with protocol and infrastructure libraries shared between them.

## Apple

- `BonjourDeviceDiscovery` browses `_p2pfiles._tcp` and decodes TXT metadata.
- `P2PFileSharingDevicePairingService` validates pairing payloads, delegates to a pairing transport, and persists trusted devices.
- `TCPFileTransferTransport` uses TLS plus a certificate fingerprint from the pairing payload, then authenticates the iPad by signing the server challenge with a local P-256 identity.
- `P2PFileSharingBrowserController`, `P2PFileSharingBrowserView`, and `P2PFileSharingQRScannerSheet` let the SDK own the browsing, pairing, scanning, and transfer flow end-to-end.
- `ManifestComparator`, transfer record storage, and the destination resolver keep the host app focused on embedding the SDK rather than reimplementing networking or persistence.
- `MockDeviceDiscovery` and `MockFileTransferTransport` provide deterministic preview/test behavior.

## Windows

- `P2PFile.Protocol` defines the authoritative frame format and message models.
- `P2PFile.Infrastructure` owns certificate loading, pairing token generation, trusted-device storage, manifest generation, share-root validation, and named-pipe control messages.
- `P2PFile.Runtime` hosts the reusable TCP/TLS server, the local control pipe, the local-network mDNS advertisement, and the bootstrap surface where a host app supplies its runtime profile.
- `P2PFile.Service` is a thin worker-style shell that imports `P2PFile.Runtime` and applies the reference appsettings-backed host profile.
- `P2PFile.Tray` is a native WinForms shell that focuses on sharing status and trusted-device management, renders the current access QR locally, and either connects to an existing runtime instance or self-hosts that same runtime in-process.

## Trust Model

- The Windows runtime presents a self-generated TLS certificate.
- The pairing payload includes the service fingerprint, an ephemeral single-use token, expiry, service identity, and optional display metadata.
- The iPad pins the Windows certificate fingerprint from the payload, then proves possession of a local P-256 key by signing the server challenge.
- The Windows runtime stores the iPad public key for future reconnect authentication.

## Runtime Flows

1. Discovery:
   Apple browses `_p2pfiles._tcp` and surfaces compatible devices.
2. Pairing:
   The Windows runtime keeps one short-lived access payload current, the sharing settings surface that code locally, and the iPad initiates pairing by scanning it.
3. Authentication:
   Reconnects skip QR scanning and use a signed challenge over the TLS channel.
4. Manifest:
   The active Windows runtime enumerates the configured share root and returns a relative-path manifest only.
5. Transfer:
   The active Windows runtime streams binary chunks, the iPad verifies size and SHA-256, then commits the file atomically.

## Design Boundaries

- No cloud account, relay server, or internet transport is required.
- No upload path, remote command execution, or arbitrary file-system browsing is exposed.
- The Windows tray QR bitmap renderer remains a platform-shell concern, while discovery, trust, and file-transfer hosting now live in the reusable runtime and shared libraries.

# Security

## Core Principles

- Encrypt all transport traffic.
- Never trust the local network by default.
- Use single-use pairing tokens instead of permanent passwords.
- Pin the Windows runtime certificate fingerprint during pairing and reconnect.
- Store long-term trust material securely on both platforms.

## Apple Side

- Trusted remote devices are stored through `KeychainPairedDeviceStore`.
- The local device identity is generated once and stored through `LocalDeviceIdentityStore`.
- The demo verifies file size and SHA-256 before promoting a temporary download into its final destination.

## Windows Side

- The Windows runtime generates and persists a self-signed P-256 TLS certificate.
- Paired iPad identities are stored as public keys in the trusted-device registry.
- Pairing tokens are random, short-lived, single-use, and rotated after expiry or a successful pairing.
- Share-root validation rejects path traversal and dangerous roots.
- The mDNS advertiser publishes only non-sensitive discovery metadata.
- The sharing settings render the access QR locally without sending the payload to any third-party service.

## Threats Addressed

- Passive network eavesdropping:
  mitigated with TLS.
- Replay of a QR payload:
  mitigated with short-lived single-use pairing tokens plus automatic rotation after expiry and successful pairing.
- Man-in-the-middle after QR scan:
  mitigated by certificate fingerprint pinning from the pairing payload.
- Stolen or stale file records:
  mitigated by local existence checks plus manifest hash/size comparison.
- Relative-path traversal:
  mitigated by path normalization on both platforms.

## Threats Still Requiring Platform Follow-Through

- Standalone Windows service installation:
  final deployment should run with the least privileged service account that still has share-root access.

## Logging Guidance

Safe to log:

- discovery lifecycle
- connection lifecycle
- manifest counts
- transfer sizes
- transfer completion
- revoke events

Do not log:

- private keys
- raw pairing tokens
- full QR payloads
- file contents
- secrets inside named-pipe control responses

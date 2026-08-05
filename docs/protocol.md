# Protocol

## Transport

- Underlying transport: TCP over TLS.
- Framing: binary envelope with JSON metadata and optional raw binary payload.
- Byte order: big-endian for integer header fields.
- Current protocol version: `1`.
- Maximum frame size: `8 MiB`.

## Frame Layout

Every frame uses this layout:

```text
0..3   UInt32   frameLength
4      UInt8    protocolVersion
5      UInt8    messageType
6..9   UInt32   metadataLength
10..N  bytes    metadata JSON
N..M   bytes    optional binary payload
```

- `frameLength` counts all bytes after the first 4-byte length field.
- `metadataLength` counts only the JSON metadata section.
- The binary payload is `frameLength - 6 - metadataLength`.

## Message Types

| Type | Direction | Purpose |
| --- | --- | --- |
| `Hello` | client -> server | announce client identity and requested protocol version |
| `HelloAck` | server -> client | confirm version and send a random challenge |
| `PairRequest` | client -> server | redeem the ephemeral pairing token and present the iPad public key |
| `PairResponse` | server -> client | confirm trust creation and return server identity metadata |
| `AuthenticateRequest` | client -> server | sign the challenge using the stored client key |
| `AuthenticateResponse` | server -> client | confirm or reject reconnect authentication |
| `ManifestRequest` | client -> server | request the current manifest |
| `ManifestResponse` | server -> client | return the manifest |
| `FileRequest` | client -> server | request one manifest item by stable file identifier |
| `FileChunk` | server -> client | stream raw file bytes in bounded chunks |
| `TransferComplete` | server -> client | declare final size and SHA-256 |
| `CancelTransfer` | either direction | terminate the current transfer |
| `Error` | either direction | return a structured failure |
| `Keepalive` | either direction | connection-health ping |

## Handshake Rules

1. Client sends `Hello`.
2. Server replies `HelloAck` with the accepted version and a random challenge.
3. Client sends either:
   `PairRequest` during first-time trust bootstrap.
   `AuthenticateRequest` on reconnect.

## Pairing

- Pairing tokens are single-use and expire after 5 minutes in the current reference implementation.
- The Windows runtime keeps one active access payload available and rotates it automatically after expiry or successful pairing.
- Token shape: 16 random bytes hex-encoded.
- Token use: single-use only.
- Verification code: first 6 token characters uppercased for short human comparison.

## Authentication

- Client key type: P-256 signing key.
- Client public key format: 65-byte uncompressed ANSI X9.63 point (`0x04 || X || Y`).
- Signature format: IEEE P1363 fixed-field concatenation over SHA-256 of the server challenge.

## Manifest Rules

- Only files beneath the configured share root are listed.
- Manifest identifiers use normalized relative paths lowercased.
- Absolute Windows paths are never returned to Apple.
- Relative paths always use `/` separators.

## File Transfer Rules

- Chunk size in the current Windows runtime: `64 KiB`.
- File chunks stream raw bytes, not Base64.
- Completion includes final size and SHA-256 so the Apple client can verify atomically before moving the file into place.

## Retry and Cancellation

- Cancellation is explicit through `CancelTransfer`.
- The Apple demo retries by issuing a new `FileRequest`.
- Reconnect auth can be retried after transient network failure as long as trust has not been revoked.

## Error Semantics

Structured `Error` metadata includes:

- `code`
- `message`

Recommended codes:

- `session_failed`
- `invalid_token`
- `revoked_device`
- `file_not_found`
- `invalid_frame`
- `auth_failed`

## Timeouts

Recommended operational defaults:

- handshake timeout: 15 seconds
- manifest request timeout: 15 seconds
- read idle timeout during transfer: 30 seconds
- failed-auth backoff: exponential with a hard cap

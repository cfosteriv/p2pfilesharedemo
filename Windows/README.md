# Windows P2P File Sharing Demo

This folder contains the Windows side of the local-network file sharing reference project. It acts as the server-side companion to the Apple demo, and it is intentionally split into reusable runtime pieces plus thin host applications.

## What The Windows Demo Does

- Advertises `_p2pfiles._tcp` over Bonjour/mDNS so Apple clients can discover it on the local network.
- Hosts a TCP/TLS endpoint for pairing, manifest requests, and file downloads.
- Maintains one short-lived pairing payload at a time and exposes runtime state to local UI over a named pipe.
- Persists trusted devices, certificate material, and runtime configuration under a configurable state root.
- Serves files from a configured share root without exposing arbitrary filesystem browsing or upload support.

## Project Map

| Project | Role |
| --- | --- |
| `P2PFile.Protocol` | Shared frame format and message models used by both platforms. |
| `P2PFile.Infrastructure` | Shared Windows support layer for certificates, pairing tokens, manifests, trusted devices, config persistence, share-root validation, and named-pipe control messages. |
| `P2PFile.Runtime` | Reusable Windows runtime that hosts the TCP/TLS server, Bonjour advertisement, local control pipe, and bootstrap APIs for other host apps. |
| `P2PFile.Service` | Thin worker-style host that runs the runtime as a standalone background process. |
| `P2PFile.Tray` | Thin WinForms host that surfaces sharing settings and trusted devices, then either connects to an existing runtime or self-hosts the same runtime in-process. |
| `P2PFile.Tests` | Coverage for protocol, manifest, control pipe, pairing token, and config behavior. |

## How The Reference App Runs

- `P2PFile.Tray` is the primary user-facing shell for this demo.
- On launch, the tray first probes the runtime control pipe.
- If a standalone runtime is already active, the tray attaches to it.
- If no runtime is active, the tray starts `EmbeddedServiceRuntime` and hosts the same endpoint in-process.
- `P2PFile.Service` is optional. It exists for deployments that prefer a dedicated background host instead of a tray-owned runtime.

That means the runtime behavior stays in one place while the host experience can vary by app type.

## Default Runtime Profile

The reference hosts use the default profile from `P2PFileReferenceRuntimeHost.Create()`:

- Display name: `P2P File Service`
- Share root: `%USERPROFILE%\Documents\P2PFileShare`
- Port: `48888`
- Service name: `p2p-file-service`
- Service type: `_p2pfiles._tcp`
- Domain: `local.`
- Pairing URI scheme: `p2pfiles`
- State root: `%LOCALAPPDATA%\P2PFileService`
- Control pipe: `P2PFileServiceControl`
- Certificate subject: `CN=P2PFileService`

`P2PFile.Service` also allows those values to be overridden from the `P2PFile` section in [`P2PFile.Service/appsettings.json`](./P2PFile.Service/appsettings.json).

## Build And Run

Open [`P2PFile.sln`](./P2PFile.sln) in Visual Studio or Rider on Windows, then build the solution or run the individual projects you need. From this `Windows` folder, the typical CLI commands are:

Typical commands:

```bash
dotnet build P2PFile.sln
dotnet test P2PFile.Tests/P2PFile.Tests.csproj
```

For a demo workflow:

1. Start `P2PFile.Tray`.
2. Confirm the share root points at the folder you want to expose.
3. Pair from the Apple demo using the tray-provided QR code or pairing payload.
4. Browse the manifest from the Apple side and download files over the local network.

Native runtime behavior is verified on Windows in addition to the cross-target macOS builds.

## CI

The root repository includes [`../.github/workflows/ci.yml`](../.github/workflows/ci.yml) to:

- run Swift package tests on macOS,
- build the iOS demo without signing on macOS,
- restore, build, and test the Windows solution on Windows.

That workflow verifies the shared build claims automatically once the repository is hosted on GitHub.

## Reusing The Runtime In Other Apps

Other Windows apps should treat `P2PFile.Runtime` as the core reusable layer and keep the host-specific UX in their own app.

Use this pattern in a worker or service-style host:

```csharp
using P2PFile.Runtime;

var builder = Host.CreateApplicationBuilder(args);

var runtimeOptions = new P2PFileRuntimeHostOptions
{
    DisplayName = "Contoso Transfer",
    ShareRoot = @"C:\Users\Alice\Documents\ContosoShare",
    Port = 48910,
    ServiceName = "contoso-transfer",
    ServiceType = "_p2pfiles._tcp",
    Domain = "local.",
    PairingUriScheme = "contosofiles",
    StateRoot = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "ContosoTransfer"),
    ControlPipeName = "ContosoTransferControl",
    CertificateSubjectName = "CN=ContosoTransfer",
};

P2PFileRuntimeBootstrap.Configure(builder, runtimeOptions);
await builder.Build().RunAsync();
```

Use this pattern in a desktop app that wants to self-host the endpoint:

```csharp
using P2PFile.Runtime;

using var runtime = EmbeddedServiceRuntime.Start(runtimeOptions);
```

Integration rules that matter:

- Give each host its own `StateRoot`, `ControlPipeName`, `ServiceName`, and `Port`.
- The tray settings window can change the advertised `ServiceType` and QR-code `PairingUriScheme` at runtime for the reference app.
- Keep QR rendering, deep links, and app branding in the shell app instead of pushing them into the runtime.
- Use the runtime control pipe if you want local settings, status snapshots, or trusted-device management from another process.

## Moving Toward A Standalone Runtime Repo

The reusable boundary in this folder is already centered on `P2PFile.Runtime`.

If you split it into its own repo later, move these projects together:

- `P2PFile.Runtime`
- `P2PFile.Infrastructure`
- `P2PFile.Protocol`

`P2PFile.Service` and `P2PFile.Tray` can then remain as example hosts or move into a separate sample repo. The runtime itself should stay focused on hosting, discovery, trust, and transfer behavior rather than app-specific UI.

## Related Docs

- [Architecture](../docs/architecture.md)
- [Protocol](../docs/protocol.md)
- [Security](../docs/security.md)
- [Pairing Sequence](../docs/pairing-sequence.md)
- [Transfer Sequence](../docs/transfer-sequence.md)

# P2PFile.Runtime

`P2PFile.Runtime` is the reusable Windows hosting layer for the P2P file sharing reference project. It is the part that other Windows apps should embed when they want the same pairing, discovery, manifest, and file-transfer behavior without copying the demo shell.

## Responsibilities

- Start and run the TCP/TLS transfer endpoint.
- Advertise the service over Bonjour/mDNS.
- Maintain the active pairing payload and rotate it when needed.
- Validate the configured share root before serving files.
- Expose a local named-pipe control surface for status, settings, and trusted-device actions.
- Provide host bootstrap APIs for both long-running services and embedded desktop-app hosting.

## Main Entry Points

| API | Purpose |
| --- | --- |
| `P2PFileRuntimeHostOptions` | Host-supplied runtime profile including share root, state root, pipe name, service identity, certificate subject, and port. |
| `P2PFileRuntimeBootstrap.Configure(...)` | Registers the runtime into an `IHostApplicationBuilder` and wires up hosted services plus persistence dependencies. |
| `EmbeddedServiceRuntime.Start(...)` | Starts the same runtime in-process for desktop apps that want to self-host the endpoint. |
| `P2PFileReferenceRuntimeHost.Create()` | Returns the reference demo defaults and is best treated as sample configuration rather than a required dependency. |
| `PairingPayloadUriCodec` | Wraps or parses pairing payloads with an app-owned URI scheme. |
| `StartupDiagnostics` | Writes startup failures to `startup-error.log` under the configured state root. |

## Runtime Shape

At runtime this project composes a few major behaviors:

- `TransferServer` accepts TLS sessions, performs pairing or reconnect authentication, serves manifests, and streams file chunks.
- `BonjourAdvertiser` publishes the `_p2pfiles._tcp` service with a minimal TXT record set.
- `P2PFileRuntimeWorker` is the hosted-service wrapper used by service-style hosts.
- `EmbeddedServiceRuntime` gives tray or desktop apps the same behavior without requiring a separate background executable.

The runtime keeps app-specific UX out of the core layer. QR rendering, tray menus, settings windows, and custom deep-link branding belong in the host app.

## Project Dependencies

This project is not fully standalone by itself yet. It currently depends on two sibling projects:

- `../P2PFile.Protocol`
- `../P2PFile.Infrastructure`

It also uses:

- `Microsoft.Extensions.Hosting`
- `MeaMod.DNS`

If you move this into its own repo later, plan to move `P2PFile.Runtime`, `P2PFile.Infrastructure`, and `P2PFile.Protocol` together, or package the lower layers separately and reference them as NuGet dependencies.

## Host Configuration

The runtime host profile is defined by `P2PFileRuntimeHostOptions`.

The options with the biggest integration impact are:

- `ShareRoot`: folder that will be exposed to remote clients.
- `StateRoot`: folder used for `service-config.json`, `service-certificate.pfx`, `trusted-devices.json`, and `startup-error.log`.
- `Port`: TCP port for the TLS transfer endpoint.
- `ServiceName`, `ServiceType`, `Domain`: Bonjour service identity.
- `PairingUriScheme`: deep-link scheme the host uses when it wraps pairing payloads into QR codes.
- `ControlPipeName`: local named-pipe endpoint used by shells such as the tray app.
- `CertificateSubjectName`: subject for the self-generated server certificate.

Use unique values for `StateRoot`, `ControlPipeName`, `ServiceName`, and `Port` when multiple apps might coexist on the same machine.

## Integration Patterns

Service or worker host:

```csharp
using P2PFile.Runtime;

var builder = Host.CreateApplicationBuilder(args);
P2PFileRuntimeBootstrap.Configure(builder, runtimeOptions);
await builder.Build().RunAsync();
```

Embedded desktop host:

```csharp
using P2PFile.Runtime;

using var runtime = EmbeddedServiceRuntime.Start(runtimeOptions);
```

App-owned pairing URI wrapper:

```csharp
using P2PFile.Runtime;

var pairingUri = PairingPayloadUriCodec.CreatePairingUri(payload, "contoso-transfer");
```

Those three entry points are enough for most host apps.

## Local Control Surface

The runtime opens a named pipe using the configured `ControlPipeName`. The reference tray uses that control surface to:

- fetch a full service snapshot
- update the share root
- update display name, port, service type, and pairing URI scheme
- revoke a trusted device

That control plane is useful when you want a separate UI process to manage a background runtime without coupling UI code into the transport server itself.

## Configuration Overrides

`P2PFileRuntimeBootstrap.Configure(...)` can merge host defaults with configuration values from the `P2PFile` section by default. The reference service host uses that behavior through [`../P2PFile.Service/appsettings.json`](../P2PFile.Service/appsettings.json).

`EmbeddedServiceRuntime.Start(...)` intentionally disables configuration merging and runs from the supplied `P2PFileRuntimeHostOptions` only.

## Standalone Repo Direction

This project is already structured like a reusable library rather than a demo-only folder. If it graduates into its own repo later, the recommended shape is:

- keep `P2PFile.Runtime` as the primary package or top-level library
- keep `P2PFile.Infrastructure` and `P2PFile.Protocol` alongside it as internal or separately packaged dependencies
- keep tray and service hosts as samples, not required runtime components

That preserves the core design goal: other apps should be able to adopt the runtime without inheriting the reference app's UI or deployment choices.

# Troubleshooting

## Apple

### The demo shows no devices in Local Network mode

- Confirm the Windows tray or standalone runtime is running.
- Confirm the runtime TCP port is reachable on the local subnet.
- Confirm multicast DNS traffic is allowed on the local network and not blocked by the Windows firewall or endpoint security tools.

### Pairing fails immediately

- Open the Windows sharing settings and use the current access code.
- Reload the sharing window if the token may have expired or already been used.
- Confirm the tray and any standalone runtime host are pointing at the same local state directory.

### Saved files do not appear where expected

- The demo app saves files into its local documents folder under `<PC Name>/<relative path>`.
- In the Files app, look under `On My iPhone` or `On My iPad` for the P2P File Demo container.
- If a file row shows `Saved`, the transfer record and the local file both exist on the device.

## Windows

### The runtime starts but no client can connect

- Check the configured TCP port in `appsettings.json`.
- Add or verify the inbound Windows Firewall rule.
- Confirm the share root exists and is accessible to the current Windows host process or service account.
- If you are using the tray-owned runtime instead of the standalone service, confirm no second Windows host is already bound to the same port.

### The tray cannot talk to the runtime

- Confirm the tray had enough time to start its embedded runtime, or that the standalone service process is already running.
- Verify both processes use the same named pipe name: `P2PFileServiceControl`.
- If both the tray and a standalone service are installed, prefer running only one Windows host at a time.

### Files disappear from the manifest unexpectedly

- The manifest only reflects files under the configured share root.
- Relative paths that escape the root are rejected.
- Files deleted or moved during enumeration will naturally disappear on the next refresh.

## Last Recorded Verification

As of August 5, 2026, these are the last recorded verification runs in this repo:

- `swift test` was verified on macOS on August 4, 2026.
- The iOS simulator build was verified from Xcode on August 4, 2026.
- `dotnet msbuild Windows/P2PFile.Tray/P2PFile.Tray.csproj /t:Build /p:RestorePackages=false /p:BuildInParallel=false /p:UseSharedCompilation=false /nr:false /v:m` succeeded for the modified Windows protocol, infrastructure, service, and tray targets on August 4, 2026.
- `dotnet test` succeeded for the shared Windows tests on August 4, 2026.
- A live Windows runtime check and true end-to-end LAN pairing demo still require a Windows host.

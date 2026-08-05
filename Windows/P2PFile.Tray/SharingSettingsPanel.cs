namespace P2PFile.Tray;

internal sealed class SharingSettingsPanel : TableLayoutPanel
{
    private readonly TrayRuntimeSession _runtimeSession;
    private readonly TrayControlClient _controlClient;
    private readonly Func<Task> _refreshRequested;
    private readonly Label _statusValue = new() { AutoSize = true };
    private readonly TextBox _displayNameTextBox = new() { Dock = DockStyle.Fill };
    private readonly NumericUpDown _portUpDown = new()
    {
        Minimum = 1,
        Maximum = 65535,
        Width = 120,
        Dock = DockStyle.Left,
    };
    private readonly Label _portHintValue = new()
    {
        AutoSize = true,
        MaximumSize = new Size(0, 0),
        ForeColor = SystemColors.GrayText,
    };
    private readonly TextBox _serviceTypeTextBox = new() { Dock = DockStyle.Fill };
    private readonly TextBox _pairingUriSchemeTextBox = new() { Dock = DockStyle.Fill };
    private readonly TextBox _shareRootTextBox = new() { Dock = DockStyle.Fill, ReadOnly = true };
    private readonly ListView _trustedDevices = new() { Dock = DockStyle.Fill, View = View.Details, FullRowSelect = true, HideSelection = false, MultiSelect = false };
    private P2PFile.Infrastructure.ServiceStatusSnapshot? _snapshot;

    public SharingSettingsPanel(TrayRuntimeSession runtimeSession, Func<Task> refreshRequested)
    {
        _runtimeSession = runtimeSession;
        _controlClient = runtimeSession.ControlClient;
        _refreshRequested = refreshRequested;

        Dock = DockStyle.Fill;
        ColumnCount = 1;
        RowCount = 3;
        Margin = new Padding(0);
        RowStyles.Add(new RowStyle(SizeType.AutoSize));
        RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        RowStyles.Add(new RowStyle(SizeType.AutoSize));

        _trustedDevices.Columns.Add("Display Name", 220);
        _trustedDevices.Columns.Add("Device ID", 240);
        _trustedDevices.Columns.Add("Paired", 120);
        _trustedDevices.Columns.Add("Last Connected", 140);

        var topPanel = new TableLayoutPanel
        {
            Dock = DockStyle.Top,
            AutoSize = true,
            ColumnCount = 2,
            Padding = new Padding(12),
        };
        topPanel.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
        topPanel.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        topPanel.Controls.Add(new Label { Text = "Service Status", AutoSize = true }, 0, 0);
        topPanel.Controls.Add(_statusValue, 1, 0);
        topPanel.Controls.Add(new Label { Text = "Display Name", AutoSize = true }, 0, 1);
        topPanel.Controls.Add(_displayNameTextBox, 1, 1);
        topPanel.Controls.Add(new Label { Text = "Port", AutoSize = true }, 0, 2);
        topPanel.Controls.Add(_portUpDown, 1, 2);
        topPanel.Controls.Add(new Label { AutoSize = true }, 0, 3);
        topPanel.Controls.Add(_portHintValue, 1, 3);
        topPanel.Controls.Add(new Label { Text = "Service Type", AutoSize = true }, 0, 4);
        topPanel.Controls.Add(_serviceTypeTextBox, 1, 4);
        topPanel.Controls.Add(new Label { AutoSize = true }, 0, 5);
        topPanel.Controls.Add(new Label
        {
            Text = "Bonjour service type, for example `_p2pfiles._tcp`.",
            AutoSize = true,
            MaximumSize = new Size(0, 0),
            ForeColor = SystemColors.GrayText,
        }, 1, 5);
        topPanel.Controls.Add(new Label { Text = "Pairing URI Scheme", AutoSize = true }, 0, 6);
        topPanel.Controls.Add(_pairingUriSchemeTextBox, 1, 6);
        topPanel.Controls.Add(new Label { AutoSize = true }, 0, 7);
        topPanel.Controls.Add(new Label
        {
            Text = "Deep-link scheme used in QR codes, for example `p2pfiles`.",
            AutoSize = true,
            MaximumSize = new Size(0, 0),
            ForeColor = SystemColors.GrayText,
        }, 1, 7);
        topPanel.Controls.Add(new Label { Text = "Shared Folder", AutoSize = true }, 0, 8);
        topPanel.Controls.Add(_shareRootTextBox, 1, 8);

        var trustedDevicesHeader = new TableLayoutPanel
        {
            Dock = DockStyle.Top,
            AutoSize = true,
            ColumnCount = 1,
            Margin = new Padding(0),
        };
        trustedDevicesHeader.Controls.Add(new Label
        {
            Text = "Trusted Devices",
            AutoSize = true,
            Font = CreateBoldFont(),
            Margin = new Padding(0, 0, 0, 6),
        });
        trustedDevicesHeader.Controls.Add(new Label
        {
            Text = "This PC keeps the current trust list. Revoke a device here if it should no longer reconnect.",
            AutoSize = true,
            MaximumSize = new Size(0, 0),
            ForeColor = SystemColors.GrayText,
            Margin = new Padding(0, 0, 0, 12),
        });

        var trustedDevicesPanel = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            ColumnCount = 1,
            RowCount = 2,
            Margin = new Padding(12, 0, 12, 0),
        };
        trustedDevicesPanel.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        trustedDevicesPanel.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        trustedDevicesPanel.Controls.Add(trustedDevicesHeader, 0, 0);
        trustedDevicesPanel.Controls.Add(_trustedDevices, 0, 1);

        var reloadButton = new Button { Text = "Reload", AutoSize = true };
        reloadButton.Click += async (_, _) => await _refreshRequested();

        var saveServiceSettingsButton = new Button { Text = "Save Service Settings", AutoSize = true };
        saveServiceSettingsButton.Click += async (_, _) => await SaveServiceSettingsAsync();

        var browseButton = new Button { Text = "Choose Shared Folder", AutoSize = true };
        browseButton.Click += async (_, _) => await BrowseForFolderAsync();

        var revokeButton = new Button { Text = "Revoke Selected Device", AutoSize = true };
        revokeButton.Click += async (_, _) => await RevokeSelectedAsync();

        var buttons = new FlowLayoutPanel
        {
            Dock = DockStyle.Top,
            AutoSize = true,
            FlowDirection = FlowDirection.LeftToRight,
            Padding = new Padding(12, 12, 12, 12),
        };
        buttons.Controls.Add(reloadButton);
        buttons.Controls.Add(saveServiceSettingsButton);
        buttons.Controls.Add(browseButton);
        buttons.Controls.Add(revokeButton);

        Controls.Add(topPanel, 0, 0);
        Controls.Add(trustedDevicesPanel, 0, 1);
        Controls.Add(buttons, 0, 2);
    }

    public void ApplySnapshot(P2PFile.Infrastructure.ServiceStatusSnapshot snapshot)
    {
        _snapshot = snapshot;
        _statusValue.Text = snapshot.IsRunning ? "Running" : "Stopped";
        _displayNameTextBox.Text = snapshot.DisplayName;
        _portUpDown.Value = Math.Min(Math.Max(snapshot.Port, 1), 65535);
        _portHintValue.Text = snapshot.ActivePort == snapshot.Port
            ? $"Active listener port: {snapshot.ActivePort}."
            : $"Active listener port: {snapshot.ActivePort}. The saved port {snapshot.Port} will be used after the background runtime restarts.";
        _serviceTypeTextBox.Text = snapshot.ServiceType;
        _pairingUriSchemeTextBox.Text = snapshot.PairingUriScheme;
        _shareRootTextBox.Text = snapshot.ShareRoot;

        _trustedDevices.Items.Clear();
        foreach (var device in snapshot.TrustedDevices.Where(device => !device.Revoked).OrderBy(device => device.DisplayName, StringComparer.CurrentCultureIgnoreCase))
        {
            var item = new ListViewItem(device.DisplayName);
            item.SubItems.Add(device.DeviceId.ToString());
            item.SubItems.Add(device.PairedAt.LocalDateTime.ToString("g"));
            item.SubItems.Add(device.LastConnectedAt?.LocalDateTime.ToString("g") ?? "Never");
            item.Tag = device.DeviceId;
            _trustedDevices.Items.Add(item);
        }
    }

    private async Task BrowseForFolderAsync()
    {
        using var dialog = new FolderBrowserDialog
        {
            Description = "Choose the folder the Windows service should expose to trusted iPads.",
            SelectedPath = _shareRootTextBox.Text,
        };
        if (dialog.ShowDialog() != DialogResult.OK)
        {
            return;
        }

        var response = await _controlClient.UpdateShareRootAsync(dialog.SelectedPath);
        if (!response.Success)
        {
            MessageBox.Show(response.ErrorMessage ?? "Failed to update the share root.", "P2P File Sharing", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return;
        }

        await _refreshRequested();
    }

    private async Task SaveServiceSettingsAsync()
    {
        var displayName = _displayNameTextBox.Text.Trim();
        var port = Decimal.ToInt32(_portUpDown.Value);
        var serviceType = _serviceTypeTextBox.Text.Trim();
        var pairingUriScheme = _pairingUriSchemeTextBox.Text.Trim();
        var previousSnapshot = _snapshot;

        if (string.IsNullOrWhiteSpace(displayName))
        {
            MessageBox.Show("A display name is required.", "P2P File Sharing", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return;
        }

        if (string.IsNullOrWhiteSpace(serviceType))
        {
            MessageBox.Show("A Bonjour service type is required.", "P2P File Sharing", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return;
        }

        if (string.IsNullOrWhiteSpace(pairingUriScheme))
        {
            MessageBox.Show("A pairing URI scheme is required.", "P2P File Sharing", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return;
        }

        if (!Uri.CheckSchemeName(pairingUriScheme))
        {
            MessageBox.Show("The pairing URI scheme must be a valid URI scheme.", "P2P File Sharing", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return;
        }

        if (previousSnapshot is not null
            && string.Equals(previousSnapshot.DisplayName, displayName, StringComparison.Ordinal)
            && previousSnapshot.Port == port
            && string.Equals(previousSnapshot.ServiceType, serviceType, StringComparison.Ordinal)
            && string.Equals(previousSnapshot.PairingUriScheme, pairingUriScheme, StringComparison.OrdinalIgnoreCase))
        {
            return;
        }

        var response = await _controlClient.UpdateServiceSettingsAsync(displayName, port, serviceType, pairingUriScheme);
        if (!response.Success || response.Snapshot is null)
        {
            MessageBox.Show(response.ErrorMessage ?? "Failed to update the service settings.", "P2P File Sharing", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return;
        }

        ApplySnapshot(response.Snapshot);

        var changedDisplayName = !string.Equals(previousSnapshot?.DisplayName, displayName, StringComparison.Ordinal);
        var changedPort = previousSnapshot?.Port != port;
        var changedServiceType = !string.Equals(previousSnapshot?.ServiceType, serviceType, StringComparison.Ordinal);
        var changedPairingUriScheme = !string.Equals(previousSnapshot?.PairingUriScheme, pairingUriScheme, StringComparison.OrdinalIgnoreCase);
        if (_runtimeSession.OwnsEmbeddedRuntime)
        {
            if (!changedPort)
            {
                await _refreshRequested();

                MessageBox.Show(
                    "Saved the sharing settings. Discovery metadata and QR settings are live now.",
                    "P2P File Sharing",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Information);
                return;
            }

            try
            {
                _runtimeSession.RestartEmbeddedRuntime();
                await _refreshRequested();

                var successMessage = $"Saved and restarted the local sharing runtime. Discovery settings are live, and the app is now listening on TCP {port}.";
                MessageBox.Show(successMessage, "P2P File Sharing", MessageBoxButtons.OK, MessageBoxIcon.Information);
            }
            catch (Exception ex)
            {
                MessageBox.Show(
                    $"Saved the settings, but the tray-owned runtime could not be restarted.{Environment.NewLine}{Environment.NewLine}{ex.Message}",
                    "P2P File Sharing",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Warning);
            }

            return;
        }

        var standaloneMessage = changedPort
            ? $"Saved the new settings. Discovery metadata and QR settings are live now. The standalone runtime is still listening on TCP {response.Snapshot.ActivePort} until it is restarted."
            : (changedDisplayName || changedServiceType || changedPairingUriScheme)
                ? "Saved the sharing settings. Discovery metadata and QR settings are live now."
                : "Saved the sharing settings.";
        MessageBox.Show(standaloneMessage, "P2P File Sharing", MessageBoxButtons.OK, MessageBoxIcon.Information);
    }

    private async Task RevokeSelectedAsync()
    {
        if (_trustedDevices.SelectedItems.Count == 0)
        {
            return;
        }

        var deviceId = (Guid)_trustedDevices.SelectedItems[0].Tag!;
        var response = await _controlClient.RevokeDeviceAsync(deviceId);
        if (!response.Success)
        {
            MessageBox.Show(response.ErrorMessage ?? "Failed to revoke the device.", "P2P File Sharing", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return;
        }

        await _refreshRequested();
    }

    private static Font CreateBoldFont()
    {
        var baseFont = SystemFonts.MessageBoxFont ?? Control.DefaultFont;
        return new Font(baseFont, FontStyle.Bold);
    }
}

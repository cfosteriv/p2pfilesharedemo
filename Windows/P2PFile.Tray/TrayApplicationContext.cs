namespace P2PFile.Tray;

internal sealed class TrayApplicationContext : ApplicationContext
{
    private readonly NotifyIcon _notifyIcon;
    private readonly TrayRuntimeSession _runtimeSession;
    private readonly TrayControlClient _controlClient;
    private readonly RunAtLoginManager _runAtLoginManager;
    private readonly ToolStripMenuItem _statusItem;
    private readonly ToolStripMenuItem _shareRootItem;
    private readonly ToolStripMenuItem _runAtLoginItem;
    private readonly System.Windows.Forms.Timer _refreshTimer;

    public TrayApplicationContext(TrayRuntimeSession runtimeSession, RunAtLoginManager runAtLoginManager)
    {
        _runtimeSession = runtimeSession;
        _controlClient = runtimeSession.ControlClient;
        _runAtLoginManager = runAtLoginManager;

        _statusItem = new ToolStripMenuItem("Status: Starting…") { Enabled = false };
        _shareRootItem = new ToolStripMenuItem("Shared Folder: Unknown") { Enabled = false };
        _runAtLoginItem = new ToolStripMenuItem("Launch at Sign-in")
        {
            Checked = _runAtLoginManager.IsEnabled(),
        };
        _runAtLoginItem.Click += (_, _) => ToggleRunAtLogin();

        var menu = new ContextMenuStrip();
        menu.Items.Add("Settings", null, (_, _) => OpenSettings());
        menu.Items.Add(_runAtLoginItem);
        menu.Items.Add("QR Code", null, (_, _) => OpenQrCode());
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(_statusItem);
        menu.Items.Add(_shareRootItem);
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add("Quit", null, (_, _) => ExitThread());

        _notifyIcon = new NotifyIcon
        {
            Text = "P2P File Sharing",
            Icon = LoadTrayIcon(),
            ContextMenuStrip = menu,
            Visible = true,
        };
        _notifyIcon.DoubleClick += (_, _) => OpenSettings();

        _refreshTimer = new System.Windows.Forms.Timer { Interval = 5000 };
        _refreshTimer.Tick += async (_, _) => await RefreshAsync();
        _refreshTimer.Start();

        _ = RefreshAsync();
    }

    protected override void ExitThreadCore()
    {
        _refreshTimer.Stop();
        _notifyIcon.Visible = false;
        _notifyIcon.Dispose();
        base.ExitThreadCore();
    }

    private void OpenSettings()
    {
        using var window = new SettingsWindow(_runtimeSession);
        window.ShowDialog();
    }

    private void OpenQrCode()
    {
        using var window = new QrCodeWindow(_controlClient);
        window.ShowDialog();
    }

    private void ToggleRunAtLogin()
    {
        var shouldEnable = !_runAtLoginItem.Checked;

        try
        {
            _runAtLoginManager.SetEnabled(shouldEnable);
            _runAtLoginItem.Checked = _runAtLoginManager.IsEnabled();
        }
        catch (Exception ex)
        {
            _runAtLoginItem.Checked = _runAtLoginManager.IsEnabled();
            MessageBox.Show(
                $"P2P File Sharing could not update the launch-at-sign-in setting.{Environment.NewLine}{Environment.NewLine}{ex.Message}",
                "P2P File Sharing",
                MessageBoxButtons.OK,
                MessageBoxIcon.Warning);
        }
    }

    private async Task RefreshAsync()
    {
        var response = await _controlClient.GetSnapshotAsync();
        if (!response.Success || response.Snapshot is null)
        {
            _statusItem.Text = $"Status: {response.ErrorMessage ?? "Unavailable"}";
            _shareRootItem.Text = "Shared Folder: Unknown";
            return;
        }

        _statusItem.Text = response.Snapshot.IsRunning ? "Status: Running" : "Status: Stopped";
        _shareRootItem.Text = $"Shared Folder: {response.Snapshot.ShareRoot}";
    }

    private static Icon LoadTrayIcon()
    {
        try
        {
            return Icon.ExtractAssociatedIcon(Application.ExecutablePath) ?? SystemIcons.Application;
        }
        catch
        {
            return SystemIcons.Application;
        }
    }
}

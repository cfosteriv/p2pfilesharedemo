namespace P2PFile.Tray;

internal sealed class SettingsWindow : Form
{
    private readonly TrayControlClient _controlClient;
    private readonly SharingSettingsPanel _settingsPanel;

    public SettingsWindow(TrayRuntimeSession runtimeSession)
    {
        _controlClient = runtimeSession.ControlClient;
        Text = "Settings";
        Width = 820;
        Height = 560;
        StartPosition = FormStartPosition.CenterScreen;

        _settingsPanel = new SharingSettingsPanel(runtimeSession, RefreshAsync);
        Controls.Add(_settingsPanel);

        Shown += async (_, _) => await RefreshAsync();
    }

    private async Task RefreshAsync()
    {
        var response = await _controlClient.GetSnapshotAsync();
        if (!response.Success || response.Snapshot is null)
        {
            MessageBox.Show(response.ErrorMessage ?? "The service is unavailable.", "P2P File Sharing", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return;
        }

        _settingsPanel.ApplySnapshot(response.Snapshot);
    }
}

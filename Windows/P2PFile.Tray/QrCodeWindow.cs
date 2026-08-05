namespace P2PFile.Tray;

public sealed class QrCodeWindow : Form
{
    private readonly TrayControlClient _controlClient;
    private readonly AccessCodeView _accessCodeView;

    public QrCodeWindow(TrayControlClient controlClient)
    {
        _controlClient = controlClient;
        Text = "QR Code";
        Width = 420;
        Height = 500;
        StartPosition = FormStartPosition.CenterScreen;
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;

        _accessCodeView = new AccessCodeView();
        var panel = new Panel
        {
            Dock = DockStyle.Fill,
            Padding = new Padding(16),
        };
        panel.Controls.Add(_accessCodeView);
        Controls.Add(panel);

        Shown += async (_, _) => await RefreshAsync();
    }

    private async Task RefreshAsync()
    {
        var response = await _controlClient.GetSnapshotAsync();
        if (!response.Success || response.Snapshot is null)
        {
            MessageBox.Show(response.ErrorMessage ?? "The QR code is unavailable.", "P2P File Sharing", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return;
        }

        _accessCodeView.ApplyPayload(response.Snapshot.ActivePairingPayload, response.Snapshot.PairingUriScheme);
    }
}

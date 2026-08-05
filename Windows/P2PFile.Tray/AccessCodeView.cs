using P2PFile.Protocol;
using P2PFile.Runtime;

namespace P2PFile.Tray;

internal sealed class AccessCodeView : TableLayoutPanel
{
    private readonly PictureBox _qrCodePicture = new() { Dock = DockStyle.Fill, SizeMode = PictureBoxSizeMode.Zoom, BackColor = Color.White };
    private readonly Label _summaryLabel = new() { AutoSize = true, MaximumSize = new Size(320, 0) };

    public AccessCodeView(string? title = null, string? helpText = null)
    {
        Dock = DockStyle.Fill;
        ColumnCount = 1;
        RowCount = 4;
        Margin = new Padding(0);
        RowStyles.Add(new RowStyle(SizeType.AutoSize));
        RowStyles.Add(new RowStyle(SizeType.AutoSize));
        RowStyles.Add(new RowStyle(SizeType.AutoSize));
        RowStyles.Add(new RowStyle(SizeType.Percent, 100));

        if (!string.IsNullOrWhiteSpace(title))
        {
            Controls.Add(new Label
            {
                Text = title,
                AutoSize = true,
                Font = CreateBoldFont(),
                Margin = new Padding(0, 0, 0, 6),
            }, 0, 0);
        }

        if (!string.IsNullOrWhiteSpace(helpText))
        {
            Controls.Add(new Label
            {
                Text = helpText,
                AutoSize = true,
                MaximumSize = new Size(320, 0),
                ForeColor = SystemColors.GrayText,
                Margin = new Padding(0, 0, 0, 12),
            }, 0, 1);
        }

        var qrFrame = new Panel
        {
            Dock = DockStyle.Top,
            Width = 320,
            Height = 320,
            Padding = new Padding(12),
            BackColor = Color.White,
            BorderStyle = BorderStyle.FixedSingle,
            Margin = new Padding(0, 0, 0, 12),
        };
        qrFrame.Controls.Add(_qrCodePicture);
        Controls.Add(qrFrame, 0, 2);
        Controls.Add(_summaryLabel, 0, 3);
    }

    public void ApplyPayload(PairingPayload? payload, string pairingUriScheme)
    {
        if (payload is null)
        {
            _summaryLabel.Text = "The current QR code is unavailable.";
            ReplaceQrImage(null);
            return;
        }

        ReplaceQrImage(PairingQrCodeRenderer.CreateBitmap(
            PairingPayloadUriCodec.CreatePairingUri(payload, pairingUriScheme)));
        _summaryLabel.Text = $"Connection Code: {payload.VerificationCode ?? "N/A"}{Environment.NewLine}Expires: {payload.ExpiresAt.LocalDateTime:g}";
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            ReplaceQrImage(null);
        }

        base.Dispose(disposing);
    }

    private void ReplaceQrImage(Image? image)
    {
        var previousImage = _qrCodePicture.Image;
        _qrCodePicture.Image = image;
        previousImage?.Dispose();
    }

    private static Font CreateBoldFont()
    {
        var baseFont = SystemFonts.MessageBoxFont ?? Control.DefaultFont;
        return new Font(baseFont, FontStyle.Bold);
    }
}

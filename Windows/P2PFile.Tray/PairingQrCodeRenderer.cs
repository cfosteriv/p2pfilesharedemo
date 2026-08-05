using QRCoder;
using System.Drawing;

namespace P2PFile.Tray;

internal static class PairingQrCodeRenderer
{
    public static Bitmap CreateBitmap(string payload)
    {
        var pngBytes = PngByteQRCodeHelper.GetQRCode(payload, QRCodeGenerator.ECCLevel.Q, 12, true);
        using var pngStream = new MemoryStream(pngBytes);
        using var image = Image.FromStream(pngStream);
        return new Bitmap(image);
    }
}

using P2PFile.Protocol;
using P2PFile.Runtime;
using System.Text;
using System.Text.Json;

namespace P2PFile.Tests;

public sealed class PairingPayloadCodecTests
{
    [Fact]
    public void GeneratesEncodedPayloadThatParsesBackToTheOriginalRecord()
    {
        var payload = new PairingPayload(
            ProtocolVersion: 1,
            DeviceId: Guid.Parse("1A340DA0-CEB8-47F6-8EAB-74B140A3BB31"),
            ServiceName: "p2p-file-service",
            ServiceType: "_p2pfiles._tcp",
            Domain: "local.",
            PairingToken: "abc123",
            ServerFingerprint: "fingerprint",
            ExpiresAt: DateTimeOffset.Parse("2026-08-04T19:00:00+00:00"),
            DisplayName: "Studio Workstation",
            VerificationCode: "ABC123");

        var encodedPayload = payload.ToEncodedPayloadString();
        var reparsed = PairingPayloadCodec.ParsePayloadString(encodedPayload);

        Assert.Equal(
            JsonSerializer.Serialize(payload, ProtocolJson.Options),
            JsonSerializer.Serialize(reparsed, ProtocolJson.Options));
    }

    [Fact]
    public void GeneratesCompactEncodedPayloadWithSwiftCompatibleTimestamp()
    {
        var payload = new PairingPayload(
            ProtocolVersion: 1,
            DeviceId: Guid.Parse("1A340DA0-CEB8-47F6-8EAB-74B140A3BB31"),
            ServiceName: "p2p-file-service",
            ServiceType: "_p2pfiles._tcp",
            Domain: "local.",
            PairingToken: "abc123",
            ServerFingerprint: "fingerprint",
            ExpiresAt: DateTimeOffset.Parse("2026-08-05T01:02:03.4567890+00:00"),
            DisplayName: "Studio Workstation",
            VerificationCode: "ABC123");

        var encodedPayload = payload.ToEncodedPayloadString();
        var payloadJson = DecodePayloadJson(encodedPayload);

        Assert.DoesNotContain('\n', payloadJson);
        Assert.Contains("\"expiresAt\":\"2026-08-05T01:02:03Z\"", payloadJson);
        Assert.DoesNotContain(".4567890", payloadJson);
    }

    [Fact]
    public void GeneratesPairingUriUsingTheHostSuppliedScheme()
    {
        var payload = new PairingPayload(
            ProtocolVersion: 1,
            DeviceId: Guid.Parse("1A340DA0-CEB8-47F6-8EAB-74B140A3BB31"),
            ServiceName: "contoso-transfer",
            ServiceType: "_p2pfiles._tcp",
            Domain: "local.",
            PairingToken: "abc123",
            ServerFingerprint: "fingerprint",
            ExpiresAt: DateTimeOffset.Parse("2026-08-05T01:02:03+00:00"),
            DisplayName: "Contoso Transfer",
            VerificationCode: "ABC123");

        var pairingUri = PairingPayloadUriCodec.CreatePairingUri(payload, "contoso-transfer");
        var reparsed = PairingPayloadUriCodec.ParsePairingUri(pairingUri, expectedScheme: "contoso-transfer");

        Assert.StartsWith("contoso-transfer://pair/", pairingUri);
        Assert.Equal(
            JsonSerializer.Serialize(payload, ProtocolJson.Options),
            JsonSerializer.Serialize(reparsed, ProtocolJson.Options));
    }

    private static string DecodePayloadJson(string encodedPayload)
    {
        return Encoding.UTF8.GetString(FromBase64Url(encodedPayload));
    }

    private static byte[] FromBase64Url(string value)
    {
        var base64 = value
            .Replace('-', '+')
            .Replace('_', '/');

        var padding = base64.Length % 4;
        if (padding > 0)
        {
            base64 = base64.PadRight(base64.Length + (4 - padding), '=');
        }

        return Convert.FromBase64String(base64);
    }
}

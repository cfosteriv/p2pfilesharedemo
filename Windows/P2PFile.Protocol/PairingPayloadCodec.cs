using System.Text;
using System.Text.Json;

namespace P2PFile.Protocol;

public static class PairingPayloadCodec
{
    public static string ToJson(this PairingPayload payload)
    {
        return JsonSerializer.Serialize(payload, ProtocolJson.Options);
    }

    public static string ToEncodedPayloadString(this PairingPayload payload)
    {
        var json = JsonSerializer.SerializeToUtf8Bytes(payload, ProtocolJson.CompactOptions);
        return ToBase64Url(json);
    }

    public static PairingPayload ParsePayloadString(string value)
    {
        var trimmed = value.Trim();
        var payloadBytes = TryDecodePayloadBytes(trimmed)
            ?? Encoding.UTF8.GetBytes(trimmed);

        return JsonSerializer.Deserialize<PairingPayload>(payloadBytes, ProtocolJson.Options)
            ?? throw new InvalidOperationException("The pairing payload could not be decoded.");
    }

    private static byte[]? TryDecodePayloadBytes(string value)
    {
        try
        {
            return FromBase64Url(value);
        }
        catch (FormatException)
        {
            return null;
        }
    }

    private static string ToBase64Url(byte[] data)
    {
        return Convert.ToBase64String(data)
            .TrimEnd('=')
            .Replace('+', '-')
            .Replace('/', '_');
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

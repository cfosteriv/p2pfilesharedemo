using P2PFile.Protocol;

namespace P2PFile.Runtime;

public static class PairingPayloadUriCodec
{
    private const string PairingRoute = "pair";

    public static string CreatePairingUri(PairingPayload payload, string uriScheme)
    {
        ArgumentNullException.ThrowIfNull(payload);

        var normalizedScheme = NormalizeScheme(uriScheme);
        return $"{normalizedScheme}://{PairingRoute}/{payload.ToEncodedPayloadString()}";
    }

    public static PairingPayload ParsePairingUri(string value, string? expectedScheme = null)
    {
        var encodedPayload = ExtractEncodedPayload(value, expectedScheme);
        return PairingPayloadCodec.ParsePayloadString(encodedPayload);
    }

    public static string ExtractEncodedPayload(string value, string? expectedScheme = null)
    {
        var trimmed = value?.Trim();
        if (string.IsNullOrWhiteSpace(trimmed))
        {
            throw new InvalidOperationException("The pairing payload could not be decoded.");
        }

        if (!Uri.TryCreate(trimmed, UriKind.Absolute, out var uri))
        {
            return trimmed;
        }

        if (!string.IsNullOrWhiteSpace(expectedScheme)
            && !string.Equals(uri.Scheme, expectedScheme, StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidOperationException($"The pairing payload used the unexpected URI scheme '{uri.Scheme}'.");
        }

        var segments = uri.AbsolutePath.Split('/', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        if (segments.Length == 0)
        {
            throw new InvalidOperationException("The pairing payload URL was missing its encoded data.");
        }

        return Uri.UnescapeDataString(segments[^1]);
    }

    private static string NormalizeScheme(string uriScheme)
    {
        var normalized = uriScheme?.Trim();
        if (string.IsNullOrWhiteSpace(normalized))
        {
            throw new InvalidOperationException("A pairing URI scheme is required.");
        }

        return normalized;
    }
}

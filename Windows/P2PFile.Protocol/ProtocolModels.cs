using System.Globalization;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace P2PFile.Protocol;

public enum P2PProtocolVersion : byte
{
    V1 = 1,
}

public enum WireMessageType : byte
{
    Hello = 1,
    HelloAck = 2,
    PairRequest = 3,
    PairResponse = 4,
    AuthenticateRequest = 5,
    AuthenticateResponse = 6,
    ManifestRequest = 7,
    ManifestResponse = 8,
    FileRequest = 9,
    FileChunk = 10,
    TransferComplete = 11,
    CancelTransfer = 12,
    Error = 13,
    Keepalive = 14,
}

public sealed record FrameEnvelope(
    P2PProtocolVersion Version,
    WireMessageType Type,
    byte[] Metadata,
    byte[] Binary);

public sealed record PairingPayload(
    int ProtocolVersion,
    Guid DeviceId,
    string ServiceName,
    string ServiceType,
    string Domain,
    string PairingToken,
    string ServerFingerprint,
    DateTimeOffset ExpiresAt,
    string? DisplayName,
    string? VerificationCode);

public sealed record RemoteFileDescriptor(
    string Id,
    string RelativePath,
    string Name,
    string? FileExtension,
    long ByteSize,
    DateTimeOffset? CreatedAt,
    DateTimeOffset ModifiedAt,
    string ContentHash,
    string? MimeType,
    bool IsEligible,
    string? LogicalGrouping);

public sealed record RemoteFileManifest(
    Guid DeviceId,
    DateTimeOffset GeneratedAt,
    IReadOnlyList<RemoteFileDescriptor> Files);

public sealed record HelloRequest(
    Guid DeviceId,
    string DisplayName,
    int RequestedVersion);

public sealed record HelloResponse(
    int AcceptedVersion,
    Guid ServerDeviceId,
    string DisplayName,
    IReadOnlyList<string> Capabilities,
    byte[] Challenge);

public sealed record PairRequest(
    string PairingToken,
    Guid ClientDeviceId,
    string ClientDisplayName,
    byte[] ClientPublicKey,
    byte[] ChallengeSignature);

public sealed record PairResponse(
    Guid DeviceId,
    string DisplayName,
    IReadOnlyList<string> Capabilities);

public sealed record AuthenticateRequest(
    Guid ClientDeviceId,
    byte[] ChallengeSignature);

public sealed record AuthenticateResponse(
    bool Accepted,
    bool Revoked);

public sealed record ManifestRequest;

public sealed record FileRequest(string FileId);

public sealed record FileChunkMetadata(
    string FileId,
    int ChunkIndex,
    int BytesInChunk,
    long TotalBytes);

public sealed record TransferCompleteMetadata(
    string FileId,
    long TotalBytes,
    string ContentHash);

public sealed record ErrorMetadata(
    string Code,
    string Message);

public static class ProtocolJson
{
    public static readonly JsonSerializerOptions Options = Create(writeIndented: true);

    public static readonly JsonSerializerOptions CompactOptions = Create(writeIndented: false);

    private static JsonSerializerOptions Create(bool writeIndented)
    {
        var options = new JsonSerializerOptions
        {
            PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
            DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
            WriteIndented = writeIndented,
        };
        options.Converters.Add(new SwiftCompatibleDateTimeOffsetConverter());
        return options;
    }
}

// Match Swift's JSONDecoder.iso8601, which rejects the fractional seconds
// System.Text.Json emits for live DateTimeOffset values by default.
internal sealed class SwiftCompatibleDateTimeOffsetConverter : JsonConverter<DateTimeOffset>
{
    private const string UtcSecondsFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'";

    public override DateTimeOffset Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
    {
        var value = reader.GetString();
        if (string.IsNullOrWhiteSpace(value))
        {
            throw new JsonException("Expected an ISO-8601 timestamp.");
        }

        if (DateTimeOffset.TryParse(
                value,
                CultureInfo.InvariantCulture,
                DateTimeStyles.AssumeUniversal | DateTimeStyles.AdjustToUniversal,
                out var parsed))
        {
            return parsed;
        }

        throw new JsonException($"Unable to parse timestamp '{value}'.");
    }

    public override void Write(Utf8JsonWriter writer, DateTimeOffset value, JsonSerializerOptions options)
    {
        writer.WriteStringValue(value.ToUniversalTime().ToString(UtcSecondsFormat, CultureInfo.InvariantCulture));
    }
}

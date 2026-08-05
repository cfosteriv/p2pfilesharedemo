using P2PFile.Protocol;

namespace P2PFile.Infrastructure;

public sealed record TrustedDevice(
    Guid DeviceId,
    string DisplayName,
    string PublicKeyBase64,
    DateTimeOffset PairedAt,
    DateTimeOffset? LastConnectedAt,
    DateTimeOffset? LastTransferAt,
    bool Revoked);

public sealed record TransferActivity(
    Guid DeviceId,
    string DisplayName,
    string RelativePath,
    long ByteSize,
    DateTimeOffset CompletedAt);

public sealed record ServiceConfiguration(
    string DisplayName,
    string ShareRoot,
    int Port,
    string ServiceName,
    string ServiceType,
    string Domain,
    string PairingUriScheme);

public sealed record ServiceStatusSnapshot(
    bool IsRunning,
    string DisplayName,
    string ShareRoot,
    int Port,
    int ActivePort,
    string ServiceType,
    string PairingUriScheme,
    IReadOnlyList<TrustedDevice> TrustedDevices,
    IReadOnlyList<TransferActivity> RecentTransfers,
    PairingPayload? ActivePairingPayload);

public enum ControlCommandType
{
    GetSnapshot,
    UpdateShareRoot,
    UpdateServiceSettings,
    RevokeDevice,
}

public sealed record ControlRequest(
    ControlCommandType Command,
    string? ShareRoot = null,
    string? DisplayName = null,
    int? Port = null,
    string? ServiceType = null,
    string? PairingUriScheme = null,
    Guid? DeviceId = null);

public sealed record ControlResponse(
    bool Success,
    string? ErrorMessage,
    ServiceStatusSnapshot? Snapshot = null);

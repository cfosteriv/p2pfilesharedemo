using System.Collections.Concurrent;
using System.Security.Cryptography;
using P2PFile.Protocol;

namespace P2PFile.Infrastructure;

public sealed class PairingTokenManager
{
    private static readonly TimeSpan TokenLifetime = TimeSpan.FromMinutes(5);
    private readonly ConcurrentDictionary<string, PairingTokenState> _tokens = new();
    private readonly ServiceConfigurationStore _configurationStore;
    private readonly Func<string> _fingerprintProvider;

    public PairingTokenManager(ServiceConfigurationStore configurationStore, Func<string> fingerprintProvider)
    {
        _configurationStore = configurationStore;
        _fingerprintProvider = fingerprintProvider;
    }

    public async Task<PairingPayload> CreatePayloadAsync(CancellationToken cancellationToken)
    {
        var configuration = await _configurationStore.LoadAsync(cancellationToken);
        var token = Convert.ToHexString(RandomNumberGenerator.GetBytes(16)).ToLowerInvariant();
        var verificationCode = token[..6].ToUpperInvariant();
        var expiresAt = DateTimeOffset.UtcNow.Add(TokenLifetime);
        _tokens.Clear();
        _tokens[token] = new PairingTokenState(token, expiresAt);

        return new PairingPayload(
            ProtocolVersion: 1,
            DeviceId: GuidUtility.FromDeterministicName(configuration.ServiceName),
            ServiceName: configuration.ServiceName,
            ServiceType: configuration.ServiceType,
            Domain: configuration.Domain,
            PairingToken: token,
            ServerFingerprint: _fingerprintProvider(),
            ExpiresAt: expiresAt,
            DisplayName: configuration.DisplayName,
            VerificationCode: verificationCode);
    }

    public bool TryUseToken(string token)
    {
        return _tokens.TryRemove(token, out var state) && state.ExpiresAt > DateTimeOffset.UtcNow;
    }

    private sealed record PairingTokenState(string Token, DateTimeOffset ExpiresAt);
}

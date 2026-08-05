using P2PFile.Infrastructure;

namespace P2PFile.Tests;

public sealed class PairingTokenManagerTests : IDisposable
{
    private readonly string _stateRoot = Path.Combine(Path.GetTempPath(), $"p2pfile-tests-{Guid.NewGuid():N}");

    [Fact]
    public async Task CreatePayloadAsync_ProducesASingleUseToken()
    {
        var manager = CreateManager();

        var payload = await manager.CreatePayloadAsync(CancellationToken.None);

        Assert.True(manager.TryUseToken(payload.PairingToken));
        Assert.False(manager.TryUseToken(payload.PairingToken));
    }

    [Fact]
    public async Task CreatePayloadAsync_UsesAShortLivedExpirationWindow()
    {
        var manager = CreateManager();
        var beforeCreation = DateTimeOffset.UtcNow;

        var payload = await manager.CreatePayloadAsync(CancellationToken.None);

        Assert.InRange(payload.ExpiresAt, beforeCreation.AddMinutes(4), beforeCreation.AddMinutes(6));
    }

    [Fact]
    public async Task CreatePayloadAsync_InvalidatesThePreviousToken()
    {
        var manager = CreateManager();

        var firstPayload = await manager.CreatePayloadAsync(CancellationToken.None);
        var secondPayload = await manager.CreatePayloadAsync(CancellationToken.None);

        Assert.False(manager.TryUseToken(firstPayload.PairingToken));
        Assert.True(manager.TryUseToken(secondPayload.PairingToken));
    }

    public void Dispose()
    {
        if (Directory.Exists(_stateRoot))
        {
            Directory.Delete(_stateRoot, recursive: true);
        }
    }

    private PairingTokenManager CreateManager()
    {
        Directory.CreateDirectory(_stateRoot);
        var configuration = new ServiceConfiguration(
            DisplayName: "Test Host",
            ShareRoot: _stateRoot,
            Port: 4242,
            ServiceName: "p2pfile-test",
            ServiceType: "_p2pfiles._tcp",
            Domain: "local.",
            PairingUriScheme: "p2pfiles");
        var configurationStore = new ServiceConfigurationStore(Path.Combine(_stateRoot, "service-config.json"), configuration);
        return new PairingTokenManager(configurationStore, () => "fingerprint");
    }
}

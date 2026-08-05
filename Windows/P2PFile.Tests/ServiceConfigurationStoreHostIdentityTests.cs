using P2PFile.Infrastructure;

namespace P2PFile.Tests;

public sealed class ServiceConfigurationStoreHostIdentityTests : IDisposable
{
    private readonly string _stateRoot = Path.Combine(Path.GetTempPath(), $"p2pfile-host-identity-tests-{Guid.NewGuid():N}");

    [Fact]
    public async Task LoadAsync_ReappliesHostOwnedIdentityWhilePreservingUserConfigurableDiscoverySettings()
    {
        Directory.CreateDirectory(_stateRoot);
        var filePath = Path.Combine(_stateRoot, "service-config.json");
        var originalHost = new ServiceConfiguration(
            DisplayName: "Original Host",
            ShareRoot: _stateRoot,
            Port: 4242,
            ServiceName: "p2pfile-original",
            ServiceType: "_p2pfiles._tcp",
            Domain: "local.",
            PairingUriScheme: "p2pfiles");
        var updatedHost = originalHost with
        {
            ServiceName = "p2pfile-second-app",
            ServiceType = "_altfiles._tcp",
            Domain = "example.local.",
            PairingUriScheme = "altpair",
        };

        var firstStore = new ServiceConfigurationStore(filePath, originalHost);
        await firstStore.LoadAsync(CancellationToken.None);

        var secondStore = new ServiceConfigurationStore(filePath, updatedHost);
        var loaded = await secondStore.LoadAsync(CancellationToken.None);

        Assert.Equal(updatedHost.ServiceName, loaded.ServiceName);
        Assert.Equal(originalHost.ServiceType, loaded.ServiceType);
        Assert.Equal(updatedHost.Domain, loaded.Domain);
        Assert.Equal(originalHost.PairingUriScheme, loaded.PairingUriScheme);
        Assert.Equal(originalHost.DisplayName, loaded.DisplayName);
        Assert.Equal(originalHost.Port, loaded.Port);
    }

    public void Dispose()
    {
        if (Directory.Exists(_stateRoot))
        {
            Directory.Delete(_stateRoot, recursive: true);
        }
    }
}

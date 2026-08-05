using P2PFile.Infrastructure;

namespace P2PFile.Tests;

public sealed class ServiceConfigurationStoreTests : IDisposable
{
    private readonly string _stateRoot = Path.Combine(Path.GetTempPath(), $"p2pfile-config-tests-{Guid.NewGuid():N}");

    [Fact]
    public async Task UpdateServiceSettingsAsync_TrimsAndPersistsDiscoverySettings()
    {
        var store = CreateStore();

        await store.UpdateServiceSettingsAsync("  Studio Workstation  ", 50001, "  _contoso-files._tcp  ", "  ContosoFiles  ", CancellationToken.None);
        var updated = await store.LoadAsync(CancellationToken.None);

        Assert.Equal("Studio Workstation", updated.DisplayName);
        Assert.Equal(50001, updated.Port);
        Assert.Equal("_contoso-files._tcp", updated.ServiceType);
        Assert.Equal("contosofiles", updated.PairingUriScheme);
    }

    [Theory]
    [InlineData("")]
    [InlineData("   ")]
    public async Task UpdateServiceSettingsAsync_RejectsBlankDisplayNames(string displayName)
    {
        var store = CreateStore();

        await Assert.ThrowsAsync<InvalidOperationException>(() => store.UpdateServiceSettingsAsync(displayName, 50001, "_contoso-files._tcp", "contosofiles", CancellationToken.None));
    }

    [Theory]
    [InlineData(0)]
    [InlineData(65536)]
    public async Task UpdateServiceSettingsAsync_RejectsPortsOutsideTheTcpRange(int port)
    {
        var store = CreateStore();

        await Assert.ThrowsAsync<InvalidOperationException>(() => store.UpdateServiceSettingsAsync("Studio Workstation", port, "_contoso-files._tcp", "contosofiles", CancellationToken.None));
    }

    [Theory]
    [InlineData("")]
    [InlineData("   ")]
    public async Task UpdateServiceSettingsAsync_RejectsBlankServiceTypes(string serviceType)
    {
        var store = CreateStore();

        await Assert.ThrowsAsync<InvalidOperationException>(() => store.UpdateServiceSettingsAsync("Studio Workstation", 50001, serviceType, "contosofiles", CancellationToken.None));
    }

    [Theory]
    [InlineData("")]
    [InlineData("   ")]
    [InlineData("contoso files")]
    [InlineData("123contoso")]
    public async Task UpdateServiceSettingsAsync_RejectsInvalidPairingUriSchemes(string pairingUriScheme)
    {
        var store = CreateStore();

        await Assert.ThrowsAsync<InvalidOperationException>(() => store.UpdateServiceSettingsAsync("Studio Workstation", 50001, "_contoso-files._tcp", pairingUriScheme, CancellationToken.None));
    }

    public void Dispose()
    {
        if (Directory.Exists(_stateRoot))
        {
            Directory.Delete(_stateRoot, recursive: true);
        }
    }

    private ServiceConfigurationStore CreateStore()
    {
        Directory.CreateDirectory(_stateRoot);

        return new ServiceConfigurationStore(
            Path.Combine(_stateRoot, "service-config.json"),
            new ServiceConfiguration(
                DisplayName: "Test Host",
                ShareRoot: _stateRoot,
                Port: 4242,
                ServiceName: "p2pfile-test",
                ServiceType: "_p2pfiles._tcp",
                Domain: "local.",
                PairingUriScheme: "p2pfiles"));
    }
}

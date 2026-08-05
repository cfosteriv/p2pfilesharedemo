using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using P2PFile.Infrastructure;

namespace P2PFile.Runtime;

public sealed class P2PFileRuntimeWorker : BackgroundService
{
    private readonly ILogger<P2PFileRuntimeWorker> _logger;
    private readonly TransferServer _transferServer;
    private readonly ServiceConfigurationStore _configurationStore;
    private readonly ServiceStatusStore _statusStore;
    private readonly StartupDiagnostics _startupDiagnostics;

    public P2PFileRuntimeWorker(
        ILogger<P2PFileRuntimeWorker> logger,
        TransferServer transferServer,
        ServiceConfigurationStore configurationStore,
        ServiceStatusStore statusStore,
        StartupDiagnostics startupDiagnostics)
    {
        _logger = logger;
        _transferServer = transferServer;
        _configurationStore = configurationStore;
        _statusStore = statusStore;
        _startupDiagnostics = startupDiagnostics;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        try
        {
            var configuration = await _configurationStore.LoadAsync(stoppingToken);
            Directory.CreateDirectory(configuration.ShareRoot);
            await _statusStore.SetRunningAsync(true, stoppingToken);
            _logger.LogInformation("P2P file service listening on TCP port {Port}.", configuration.Port);
            await _transferServer.RunAsync(stoppingToken);
        }
        catch (Exception ex)
        {
            _startupDiagnostics.Write("Hosted worker failed while starting or running the local endpoint.", ex);
            throw;
        }
        finally
        {
            await _statusStore.SetRunningAsync(false, CancellationToken.None);
            _logger.LogInformation("P2P file service stopped.");
        }
    }
}

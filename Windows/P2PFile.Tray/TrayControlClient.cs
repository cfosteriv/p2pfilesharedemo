using P2PFile.Infrastructure;

namespace P2PFile.Tray;

public sealed class TrayControlClient : IDisposable
{
    private static readonly TimeSpan RequestTimeout = TimeSpan.FromSeconds(3);
    private readonly ControlPipeClient _pipeClient;
    private readonly CancellationTokenSource _shutdown = new();

    public TrayControlClient(ControlPipeClient pipeClient)
    {
        _pipeClient = pipeClient;
    }

    public Task<ControlResponse> GetSnapshotAsync()
    {
        return SendAsync(new ControlRequest(ControlCommandType.GetSnapshot));
    }

    public Task<ControlResponse> UpdateShareRootAsync(string shareRoot)
    {
        return SendAsync(new ControlRequest(ControlCommandType.UpdateShareRoot, ShareRoot: shareRoot));
    }

    public Task<ControlResponse> UpdateServiceSettingsAsync(string displayName, int port, string serviceType, string pairingUriScheme)
    {
        return SendAsync(new ControlRequest(
            ControlCommandType.UpdateServiceSettings,
            DisplayName: displayName,
            Port: port,
            ServiceType: serviceType,
            PairingUriScheme: pairingUriScheme));
    }

    public Task<ControlResponse> RevokeDeviceAsync(Guid deviceId)
    {
        return SendAsync(new ControlRequest(ControlCommandType.RevokeDevice, DeviceId: deviceId));
    }

    public void Dispose()
    {
        _shutdown.Cancel();
        _shutdown.Dispose();
    }

    private async Task<ControlResponse> SendAsync(ControlRequest request)
    {
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(_shutdown.Token);
        timeout.CancelAfter(RequestTimeout);

        try
        {
            return await _pipeClient.SendAsync(request, timeout.Token);
        }
        catch (OperationCanceledException) when (_shutdown.IsCancellationRequested)
        {
            return new ControlResponse(false, "The tray application is shutting down.");
        }
        catch (OperationCanceledException)
        {
            return new ControlResponse(false, "The local background endpoint did not respond in time.");
        }
        catch (Exception ex)
        {
            return new ControlResponse(false, ex.Message);
        }
    }
}

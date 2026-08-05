using P2PFile.Protocol;

namespace P2PFile.Infrastructure;

public sealed class ServiceStatusStore
{
    private readonly SemaphoreSlim _gate = new(1, 1);
    private readonly List<TransferActivity> _recentTransfers = new();
    private PairingPayload? _activePairingPayload;
    private bool _isRunning;

    public async Task SetRunningAsync(bool isRunning, CancellationToken cancellationToken)
    {
        await _gate.WaitAsync(cancellationToken);
        try
        {
            _isRunning = isRunning;
        }
        finally
        {
            _gate.Release();
        }
    }

    public async Task SetActivePairingPayloadAsync(PairingPayload payload, CancellationToken cancellationToken)
    {
        await _gate.WaitAsync(cancellationToken);
        try
        {
            _activePairingPayload = payload;
        }
        finally
        {
            _gate.Release();
        }
    }

    public async Task<PairingPayload?> GetActivePairingPayloadAsync(CancellationToken cancellationToken)
    {
        await _gate.WaitAsync(cancellationToken);
        try
        {
            return _activePairingPayload;
        }
        finally
        {
            _gate.Release();
        }
    }

    public async Task AddTransferAsync(TransferActivity activity, CancellationToken cancellationToken)
    {
        await _gate.WaitAsync(cancellationToken);
        try
        {
            _recentTransfers.Insert(0, activity);
            while (_recentTransfers.Count > 25)
            {
                _recentTransfers.RemoveAt(_recentTransfers.Count - 1);
            }
        }
        finally
        {
            _gate.Release();
        }
    }

    public async Task<ServiceStatusSnapshot> SnapshotAsync(
        ServiceConfiguration configuration,
        int activePort,
        IReadOnlyList<TrustedDevice> trustedDevices,
        CancellationToken cancellationToken)
    {
        await _gate.WaitAsync(cancellationToken);
        try
        {
            return new ServiceStatusSnapshot(
                _isRunning,
                configuration.DisplayName,
                configuration.ShareRoot,
                configuration.Port,
                activePort,
                configuration.ServiceType,
                configuration.PairingUriScheme,
                trustedDevices,
                _recentTransfers.ToList(),
                _activePairingPayload);
        }
        finally
        {
            _gate.Release();
        }
    }
}

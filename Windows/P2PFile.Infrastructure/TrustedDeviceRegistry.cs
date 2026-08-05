using System.Text.Json;
using P2PFile.Protocol;

namespace P2PFile.Infrastructure;

public sealed class TrustedDeviceRegistry
{
    private readonly string _filePath;
    private readonly SemaphoreSlim _gate = new(1, 1);

    public TrustedDeviceRegistry(string filePath)
    {
        _filePath = filePath;
    }

    public async Task<IReadOnlyList<TrustedDevice>> LoadAsync(CancellationToken cancellationToken)
    {
        await _gate.WaitAsync(cancellationToken);
        try
        {
            return await LoadUnsafeAsync(cancellationToken);
        }
        finally
        {
            _gate.Release();
        }
    }

    public async Task<TrustedDevice?> FindAsync(Guid deviceId, CancellationToken cancellationToken)
    {
        var devices = await LoadAsync(cancellationToken);
        return devices.SingleOrDefault(device => device.DeviceId == deviceId);
    }

    public async Task UpsertAsync(TrustedDevice device, CancellationToken cancellationToken)
    {
        await _gate.WaitAsync(cancellationToken);
        try
        {
            var devices = (await LoadUnsafeAsync(cancellationToken)).ToList();
            var index = devices.FindIndex(existing => existing.DeviceId == device.DeviceId);
            if (index >= 0)
            {
                devices[index] = device;
            }
            else
            {
                devices.Add(device);
            }

            await PersistUnsafeAsync(devices, cancellationToken);
        }
        finally
        {
            _gate.Release();
        }
    }

    public async Task RevokeAsync(Guid deviceId, CancellationToken cancellationToken)
    {
        await _gate.WaitAsync(cancellationToken);
        try
        {
            var devices = (await LoadUnsafeAsync(cancellationToken))
                .Select(device => device.DeviceId == deviceId ? device with { Revoked = true } : device)
                .ToList();
            await PersistUnsafeAsync(devices, cancellationToken);
        }
        finally
        {
            _gate.Release();
        }
    }

    private async Task<IReadOnlyList<TrustedDevice>> LoadUnsafeAsync(CancellationToken cancellationToken)
    {
        if (!File.Exists(_filePath))
        {
            return Array.Empty<TrustedDevice>();
        }

        await using var stream = File.OpenRead(_filePath);
        var devices = await JsonSerializer.DeserializeAsync<List<TrustedDevice>>(stream, ProtocolJson.Options, cancellationToken);
        return devices is null ? Array.Empty<TrustedDevice>() : devices;
    }

    private async Task PersistUnsafeAsync(IReadOnlyList<TrustedDevice> devices, CancellationToken cancellationToken)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(_filePath)!);
        await using var stream = File.Create(_filePath);
        await JsonSerializer.SerializeAsync(stream, devices, ProtocolJson.Options, cancellationToken);
    }
}

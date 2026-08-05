using P2PFile.Infrastructure;
using P2PFile.Runtime;

namespace P2PFile.Tray;

internal sealed class TrayRuntimeSession : IDisposable
{
    private readonly object _gate = new();
    private readonly P2PFileRuntimeHostOptions _runtimeOptions;
    private readonly string _pipeName;
    private readonly StartupDiagnostics _startupDiagnostics;
    private EmbeddedServiceRuntime? _embeddedHost;
    private bool _disposed;

    private TrayRuntimeSession(P2PFileRuntimeHostOptions runtimeOptions, TrayControlClient controlClient, EmbeddedServiceRuntime? embeddedHost)
    {
        _runtimeOptions = runtimeOptions.Clone();
        _pipeName = _runtimeOptions.ControlPipeName;
        _startupDiagnostics = new StartupDiagnostics(_runtimeOptions.StateRoot);
        ControlClient = controlClient;
        _embeddedHost = embeddedHost;
    }

    public TrayControlClient ControlClient { get; }

    public bool OwnsEmbeddedRuntime
    {
        get
        {
            lock (_gate)
            {
                return _embeddedHost is not null;
            }
        }
    }

    public static TrayRuntimeSession Start(P2PFileRuntimeHostOptions runtimeOptions)
    {
        ArgumentNullException.ThrowIfNull(runtimeOptions);

        var normalizedOptions = P2PFileRuntimeBootstrap.NormalizeHostOptions(runtimeOptions);
        var pipeName = normalizedOptions.ControlPipeName;
        if (ProbeServiceAsync(pipeName, TimeSpan.FromMilliseconds(750)).GetAwaiter().GetResult())
        {
            return new TrayRuntimeSession(normalizedOptions, new TrayControlClient(new ControlPipeClient(pipeName)), embeddedHost: null);
        }

        EmbeddedServiceRuntime? embeddedHost = null;
        try
        {
            embeddedHost = EmbeddedServiceRuntime.Start(normalizedOptions);

            if (!ProbeServiceAsync(pipeName, TimeSpan.FromSeconds(5)).GetAwaiter().GetResult())
            {
                new StartupDiagnostics(normalizedOptions.StateRoot).Write("The tray started the embedded runtime, but the local control pipe did not become reachable within 5 seconds.");
                throw new InvalidOperationException("The embedded TCP and Bonjour runtime did not expose its local control endpoint.");
            }

            return new TrayRuntimeSession(normalizedOptions, new TrayControlClient(new ControlPipeClient(pipeName)), embeddedHost);
        }
        catch
        {
            if (embeddedHost is not null)
            {
                embeddedHost.Dispose();
            }

            if (ProbeServiceAsync(pipeName, TimeSpan.FromSeconds(2)).GetAwaiter().GetResult())
            {
                return new TrayRuntimeSession(normalizedOptions, new TrayControlClient(new ControlPipeClient(pipeName)), embeddedHost: null);
            }

            throw;
        }
    }

    public void Dispose()
    {
        EmbeddedServiceRuntime? embeddedHost;

        lock (_gate)
        {
            if (_disposed)
            {
                return;
            }

            _disposed = true;
            embeddedHost = _embeddedHost;
            _embeddedHost = null;
        }

        ControlClient.Dispose();
        embeddedHost?.Dispose();
    }

    public void RestartEmbeddedRuntime()
    {
        EmbeddedServiceRuntime? hostToDispose;
        lock (_gate)
        {
            ThrowIfDisposed();

            hostToDispose = _embeddedHost
                ?? throw new InvalidOperationException("The tray is connected to a standalone runtime and cannot restart it.");
            _embeddedHost = null;
        }

        hostToDispose.Dispose();

        EmbeddedServiceRuntime? restartedHost = null;
        try
        {
            restartedHost = EmbeddedServiceRuntime.Start(_runtimeOptions);
            if (!ProbeServiceAsync(_pipeName, TimeSpan.FromSeconds(5)).GetAwaiter().GetResult())
            {
                _startupDiagnostics.Write("The tray restarted the embedded runtime, but the local control pipe did not become reachable within 5 seconds.");
                throw new InvalidOperationException("The embedded TCP and Bonjour runtime did not become reachable after restarting.");
            }

            lock (_gate)
            {
                ThrowIfDisposed();
                _embeddedHost = restartedHost;
                restartedHost = null;
            }
        }
        catch
        {
            restartedHost?.Dispose();
            throw;
        }
    }

    private static async Task<bool> ProbeServiceAsync(string pipeName, TimeSpan timeout)
    {
        using var cancellation = new CancellationTokenSource(timeout);

        try
        {
            var response = await new ControlPipeClient(pipeName).SendAsync(
                new ControlRequest(ControlCommandType.GetSnapshot),
                cancellation.Token);
            return response.Success;
        }
        catch (OperationCanceledException)
        {
            return false;
        }
        catch (Exception)
        {
            return false;
        }
    }

    private void ThrowIfDisposed()
    {
        if (_disposed)
        {
            throw new ObjectDisposedException(nameof(TrayRuntimeSession));
        }
    }
}

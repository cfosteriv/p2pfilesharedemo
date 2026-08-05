using Microsoft.Extensions.Hosting;

namespace P2PFile.Runtime;

public sealed class EmbeddedServiceRuntime : IDisposable
{
    private readonly IHost _host;

    private EmbeddedServiceRuntime(IHost host)
    {
        _host = host;
    }

    public static EmbeddedServiceRuntime Start(P2PFileRuntimeHostOptions hostOptions)
    {
        ArgumentNullException.ThrowIfNull(hostOptions);

        var normalizedOptions = P2PFileRuntimeBootstrap.NormalizeHostOptions(hostOptions);
        var startupDiagnostics = new StartupDiagnostics(normalizedOptions.StateRoot);
        startupDiagnostics.Clear();

        try
        {
            var builder = Host.CreateApplicationBuilder(new HostApplicationBuilderSettings
            {
                Args = [],
                ContentRootPath = AppContext.BaseDirectory,
                ApplicationName = typeof(EmbeddedServiceRuntime).Assembly.GetName().Name,
            });

            P2PFileRuntimeBootstrap.Configure(builder, normalizedOptions, includeConfigurationOverrides: false);

            var host = builder.Build();
            host.StartAsync().GetAwaiter().GetResult();
            return new EmbeddedServiceRuntime(host);
        }
        catch (Exception ex)
        {
            startupDiagnostics.Write("Embedded runtime startup failed.", ex);
            throw;
        }
    }

    public void Dispose()
    {
        try
        {
            _host.StopAsync().GetAwaiter().GetResult();
        }
        finally
        {
            _host.Dispose();
        }
    }
}

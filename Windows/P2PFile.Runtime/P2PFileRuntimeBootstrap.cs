using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using P2PFile.Infrastructure;

namespace P2PFile.Runtime;

public static class P2PFileRuntimeBootstrap
{
    public const string DefaultConfigurationSectionName = "P2PFile";

    public static void Configure(
        IHostApplicationBuilder builder,
        P2PFileRuntimeHostOptions hostOptions,
        bool includeConfigurationOverrides = true,
        string configurationSectionName = DefaultConfigurationSectionName)
    {
        ArgumentNullException.ThrowIfNull(builder);
        ArgumentNullException.ThrowIfNull(hostOptions);

        var resolvedOptions = ResolveOptions(
            builder.Configuration,
            hostOptions,
            includeConfigurationOverrides,
            configurationSectionName);

        builder.Services.AddSingleton(resolvedOptions);
        builder.Services.AddSingleton(sp => new StartupDiagnostics(sp.GetRequiredService<P2PFileRuntimeHostOptions>().StateRoot));
        builder.Services.AddSingleton(sp =>
        {
            var options = sp.GetRequiredService<P2PFileRuntimeHostOptions>();
            Directory.CreateDirectory(options.StateRoot);
            var defaultConfiguration = new ServiceConfiguration(
                options.DisplayName,
                options.ShareRoot,
                options.Port,
                options.ServiceName,
                options.ServiceType,
                options.Domain,
                options.PairingUriScheme);
            return new ServiceConfigurationStore(Path.Combine(options.StateRoot, "service-config.json"), defaultConfiguration);
        });
        builder.Services.AddSingleton(sp =>
        {
            var options = sp.GetRequiredService<P2PFileRuntimeHostOptions>();
            return new ServerCertificateProvider(
                Path.Combine(options.StateRoot, "service-certificate.pfx"),
                options.CertificateSubjectName);
        });
        builder.Services.AddSingleton(sp =>
        {
            var options = sp.GetRequiredService<P2PFileRuntimeHostOptions>();
            return new TrustedDeviceRegistry(Path.Combine(options.StateRoot, "trusted-devices.json"));
        });
        builder.Services.AddSingleton<ShareRootValidator>();
        builder.Services.AddSingleton<ManifestBuilder>();
        builder.Services.AddSingleton<ServiceStatusStore>();
        builder.Services.AddSingleton<BonjourAdvertiser>();
        builder.Services.AddSingleton<PairingTokenManager>(sp =>
        {
            var configurationStore = sp.GetRequiredService<ServiceConfigurationStore>();
            var certificate = sp.GetRequiredService<ServerCertificateProvider>().LoadOrCreate();
            return new PairingTokenManager(configurationStore, () => ServerCertificateProvider.ComputeFingerprintSha256(certificate));
        });
        builder.Services.AddSingleton<TransferServer>();
        builder.Services.AddHostedService<P2PFileRuntimeWorker>();
    }

    public static P2PFileRuntimeHostOptions NormalizeHostOptions(P2PFileRuntimeHostOptions options)
    {
        ArgumentNullException.ThrowIfNull(options);

        if (options.Port is < 1 or > 65535)
        {
            throw new InvalidOperationException("The port must be between 1 and 65535.");
        }

        return new P2PFileRuntimeHostOptions
        {
            DisplayName = NormalizeRequiredString(options.DisplayName, "A display name is required."),
            ShareRoot = NormalizePath(options.ShareRoot, "A share root path is required."),
            Port = options.Port,
            ServiceName = NormalizeRequiredString(options.ServiceName, "A service name is required."),
            ServiceType = NormalizeRequiredString(options.ServiceType, "A service type is required."),
            Domain = NormalizeRequiredString(options.Domain, "A service domain is required."),
            PairingUriScheme = NormalizeUriScheme(options.PairingUriScheme, "A pairing URI scheme is required."),
            StateRoot = NormalizePath(options.StateRoot, "A state root path is required."),
            ControlPipeName = NormalizeRequiredString(options.ControlPipeName, "A control pipe name is required."),
            CertificateSubjectName = NormalizeRequiredString(options.CertificateSubjectName, "A certificate subject name is required."),
        };
    }

    private static P2PFileRuntimeHostOptions ResolveOptions(
        IConfiguration configuration,
        P2PFileRuntimeHostOptions hostOptions,
        bool includeConfigurationOverrides,
        string configurationSectionName)
    {
        var resolvedOptions = hostOptions.Clone();
        if (includeConfigurationOverrides)
        {
            var sectionName = string.IsNullOrWhiteSpace(configurationSectionName)
                ? DefaultConfigurationSectionName
                : configurationSectionName.Trim();
            configuration.GetSection(sectionName).Bind(resolvedOptions);
        }

        return NormalizeHostOptions(resolvedOptions);
    }

    private static string NormalizePath(string path, string errorMessage)
    {
        var normalized = NormalizeRequiredString(path, errorMessage);
        return Path.GetFullPath(Environment.ExpandEnvironmentVariables(normalized));
    }

    private static string NormalizeRequiredString(string value, string errorMessage)
    {
        var normalized = value?.Trim();
        if (string.IsNullOrWhiteSpace(normalized))
        {
            throw new InvalidOperationException(errorMessage);
        }

        return normalized;
    }

    private static string NormalizeUriScheme(string value, string errorMessage)
    {
        var normalized = NormalizeRequiredString(value, errorMessage);
        if (!Uri.CheckSchemeName(normalized))
        {
            throw new InvalidOperationException("The pairing URI scheme must be a valid URI scheme.");
        }

        return normalized.ToLowerInvariant();
    }
}

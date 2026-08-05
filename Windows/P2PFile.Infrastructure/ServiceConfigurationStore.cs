using System.Text.Json;
using P2PFile.Protocol;

namespace P2PFile.Infrastructure;

public sealed class ServiceConfigurationStore
{
    private readonly string _filePath;
    private readonly SemaphoreSlim _gate = new(1, 1);
    private readonly ServiceConfiguration _fallbackConfiguration;

    public ServiceConfigurationStore(string filePath, ServiceConfiguration fallbackConfiguration)
    {
        _filePath = filePath;
        _fallbackConfiguration = fallbackConfiguration;
    }

    public async Task<ServiceConfiguration> LoadAsync(CancellationToken cancellationToken)
    {
        await _gate.WaitAsync(cancellationToken);
        try
        {
            if (!File.Exists(_filePath))
            {
                var normalizedFallback = ApplyHostConfiguration(_fallbackConfiguration);
                await PersistUnsafeAsync(normalizedFallback, cancellationToken);
                return normalizedFallback;
            }

            ServiceConfiguration configuration;
            await using (var stream = File.OpenRead(_filePath))
            {
                configuration = await JsonSerializer.DeserializeAsync<ServiceConfiguration>(stream, ProtocolJson.Options, cancellationToken)
                    ?? _fallbackConfiguration;
            }

            var normalized = ApplyHostConfiguration(configuration);

            if (!Equals(configuration, normalized))
            {
                await PersistUnsafeAsync(normalized, cancellationToken);
            }

            return normalized;
        }
        finally
        {
            _gate.Release();
        }
    }

    public async Task UpdateShareRootAsync(string shareRoot, ShareRootValidator validator, CancellationToken cancellationToken)
    {
        var validatedRoot = validator.ValidateShareRoot(shareRoot);
        await _gate.WaitAsync(cancellationToken);
        try
        {
            var current = await LoadUnsafeAsync(cancellationToken);
            await PersistUnsafeAsync(current with { ShareRoot = validatedRoot }, cancellationToken);
        }
        finally
        {
            _gate.Release();
        }
    }

    public async Task UpdateServiceSettingsAsync(
        string displayName,
        int port,
        string serviceType,
        string pairingUriScheme,
        CancellationToken cancellationToken)
    {
        var normalizedDisplayName = NormalizeDisplayName(displayName);
        var normalizedPort = NormalizePort(port);
        var normalizedServiceType = NormalizeRequiredValue(serviceType, "A service type is required.");
        var normalizedPairingUriScheme = NormalizeUriScheme(pairingUriScheme, "A pairing URI scheme is required.");

        await _gate.WaitAsync(cancellationToken);
        try
        {
            var current = await LoadUnsafeAsync(cancellationToken);
            await PersistUnsafeAsync(
                current with
                {
                    DisplayName = normalizedDisplayName,
                    Port = normalizedPort,
                    ServiceType = normalizedServiceType,
                    PairingUriScheme = normalizedPairingUriScheme,
                },
                cancellationToken);
        }
        finally
        {
            _gate.Release();
        }
    }

    private async Task<ServiceConfiguration> LoadUnsafeAsync(CancellationToken cancellationToken)
    {
        if (!File.Exists(_filePath))
        {
            return ApplyHostConfiguration(_fallbackConfiguration);
        }

        await using var stream = File.OpenRead(_filePath);
        var configuration = await JsonSerializer.DeserializeAsync<ServiceConfiguration>(stream, ProtocolJson.Options, cancellationToken)
            ?? _fallbackConfiguration;
        return ApplyHostConfiguration(configuration);
    }

    private async Task PersistUnsafeAsync(ServiceConfiguration configuration, CancellationToken cancellationToken)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(_filePath)!);
        await using var stream = File.Create(_filePath);
        await JsonSerializer.SerializeAsync(stream, configuration, ProtocolJson.Options, cancellationToken);
    }

    private ServiceConfiguration ApplyHostConfiguration(ServiceConfiguration configuration)
    {
        return configuration with
        {
            DisplayName = NormalizeDisplayName(configuration.DisplayName),
            ShareRoot = NormalizePath(configuration.ShareRoot),
            Port = NormalizePort(configuration.Port),
            ServiceName = NormalizeRequiredValue(_fallbackConfiguration.ServiceName, "A service name is required."),
            ServiceType = NormalizeConfiguredValue(configuration.ServiceType, _fallbackConfiguration.ServiceType, "A service type is required."),
            Domain = NormalizeRequiredValue(_fallbackConfiguration.Domain, "A service domain is required."),
            PairingUriScheme = NormalizeUriScheme(configuration.PairingUriScheme, _fallbackConfiguration.PairingUriScheme, "A pairing URI scheme is required."),
        };
    }

    private static string NormalizeDisplayName(string displayName)
    {
        var normalized = displayName?.Trim();
        if (string.IsNullOrWhiteSpace(normalized))
        {
            throw new InvalidOperationException("A display name is required.");
        }

        return normalized;
    }

    private static string NormalizePath(string path)
    {
        if (string.IsNullOrWhiteSpace(path))
        {
            return path;
        }

        return Path.GetFullPath(Environment.ExpandEnvironmentVariables(path));
    }

    private static string NormalizeRequiredValue(string value, string errorMessage)
    {
        var normalized = value?.Trim();
        if (string.IsNullOrWhiteSpace(normalized))
        {
            throw new InvalidOperationException(errorMessage);
        }

        return normalized;
    }

    private static string NormalizeConfiguredValue(string value, string fallbackValue, string errorMessage)
    {
        return NormalizeRequiredValue(
            string.IsNullOrWhiteSpace(value) ? fallbackValue : value,
            errorMessage);
    }

    private static string NormalizeUriScheme(string value, string fallbackValue, string errorMessage)
    {
        return NormalizeUriScheme(
            string.IsNullOrWhiteSpace(value) ? fallbackValue : value,
            errorMessage);
    }

    private static string NormalizeUriScheme(string value, string errorMessage)
    {
        var normalized = NormalizeRequiredValue(value, errorMessage);
        if (!Uri.CheckSchemeName(normalized))
        {
            throw new InvalidOperationException("The pairing URI scheme must be a valid URI scheme.");
        }

        return normalized.ToLowerInvariant();
    }

    private static int NormalizePort(int port)
    {
        if (port is < 1 or > 65535)
        {
            throw new InvalidOperationException("The port must be between 1 and 65535.");
        }

        return port;
    }
}

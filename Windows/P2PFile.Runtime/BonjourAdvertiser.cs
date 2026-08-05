using Microsoft.Extensions.Logging;
using MeaMod.DNS.Multicast;
using P2PFile.Infrastructure;

namespace P2PFile.Runtime;

public sealed class BonjourAdvertiser : IDisposable
{
    private readonly ILogger<BonjourAdvertiser> _logger;
    private ServiceDiscovery? _serviceDiscovery;
    private ServiceProfile? _serviceProfile;

    public BonjourAdvertiser(ILogger<BonjourAdvertiser> logger)
    {
        _logger = logger;
    }

    public void Start(ServiceConfiguration configuration)
    {
        Stop();

        var profile = new ServiceProfile(configuration.ServiceName, configuration.ServiceType, (ushort)configuration.Port, addresses: null);
        profile.AddProperty("deviceID", GuidUtility.FromDeterministicName(configuration.ServiceName).ToString());
        profile.AddProperty("displayName", configuration.DisplayName);
        profile.AddProperty("protocolVersion", ServiceDiscoveryMetadata.ProtocolVersion.ToString());
        profile.AddProperty("capabilities", string.Join(',', ServiceDiscoveryMetadata.Capabilities));
        profile.AddProperty("pairingRequired", bool.TrueString.ToLowerInvariant());

        var discovery = new ServiceDiscovery();
        discovery.Advertise(profile);

        _serviceDiscovery = discovery;
        _serviceProfile = profile;

        _logger.LogInformation(
            "Advertising {InstanceName} via mDNS as {ServiceType} on port {Port}.",
            configuration.ServiceName,
            configuration.ServiceType,
            configuration.Port);
    }

    public void Stop()
    {
        if (_serviceDiscovery is null)
        {
            return;
        }

        try
        {
            if (_serviceProfile is not null)
            {
                _serviceDiscovery.Unadvertise(_serviceProfile);
            }
            else
            {
                _serviceDiscovery.Unadvertise();
            }
        }
        catch (Exception ex)
        {
            _logger.LogDebug(ex, "Failed to unregister the mDNS advertisement cleanly.");
        }

        _serviceDiscovery.Dispose();
        _serviceDiscovery = null;
        _serviceProfile = null;
    }

    public void Dispose()
    {
        Stop();
    }
}

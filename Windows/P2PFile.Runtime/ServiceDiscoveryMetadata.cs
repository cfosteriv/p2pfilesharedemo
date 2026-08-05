using P2PFile.Protocol;

namespace P2PFile.Runtime;

internal static class ServiceDiscoveryMetadata
{
    public static readonly string[] Capabilities = ["manifest", "download", "hash-sha256", "pairing"];

    public static int ProtocolVersion => (int)P2PProtocolVersion.V1;
}

using System.Security.Cryptography;
using System.Text;

namespace P2PFile.Infrastructure;

public static class GuidUtility
{
    public static Guid FromDeterministicName(string value)
    {
        var hash = SHA256.HashData(Encoding.UTF8.GetBytes(value));
        Span<byte> bytes = stackalloc byte[16];
        hash.AsSpan(0, 16).CopyTo(bytes);
        return new Guid(bytes);
    }
}

using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;

namespace P2PFile.Infrastructure;

public sealed class ServerCertificateProvider
{
    private readonly string _certificatePath;
    private readonly string _certificateSubjectName;

    public ServerCertificateProvider(string certificatePath, string certificateSubjectName)
    {
        _certificatePath = certificatePath;
        _certificateSubjectName = certificateSubjectName;
    }

    public X509Certificate2 LoadOrCreate()
    {
        Directory.CreateDirectory(Path.GetDirectoryName(_certificatePath)!);
        if (File.Exists(_certificatePath))
        {
            return X509CertificateLoader.LoadPkcs12FromFile(_certificatePath, string.Empty);
        }

        using var ecdsa = ECDsa.Create(ECCurve.NamedCurves.nistP256);
        var request = new CertificateRequest(_certificateSubjectName, ecdsa, HashAlgorithmName.SHA256);
        request.CertificateExtensions.Add(new X509BasicConstraintsExtension(false, false, 0, false));
        request.CertificateExtensions.Add(new X509KeyUsageExtension(X509KeyUsageFlags.DigitalSignature, false));
        request.CertificateExtensions.Add(new X509SubjectKeyIdentifierExtension(request.PublicKey, false));
        var certificate = request.CreateSelfSigned(DateTimeOffset.UtcNow.AddDays(-1), DateTimeOffset.UtcNow.AddYears(5));
        var persisted = X509CertificateLoader.LoadPkcs12(
            certificate.Export(X509ContentType.Pfx, string.Empty),
            string.Empty,
            X509KeyStorageFlags.Exportable,
            Pkcs12LoaderLimits.Defaults);
        File.WriteAllBytes(_certificatePath, persisted.Export(X509ContentType.Pfx, string.Empty));
        return persisted;
    }

    public static string ComputeFingerprintSha256(X509Certificate2 certificate)
    {
        return Convert.ToHexString(SHA256.HashData(certificate.RawData)).ToLowerInvariant();
    }
}

using P2PFile.Protocol;
using System.Security.Cryptography;

namespace P2PFile.Infrastructure;

public sealed class ManifestBuilder
{
    private readonly ShareRootValidator _validator;

    public ManifestBuilder(ShareRootValidator validator)
    {
        _validator = validator;
    }

    public async Task<RemoteFileManifest> BuildAsync(Guid deviceId, string shareRoot, CancellationToken cancellationToken)
    {
        var validatedRoot = _validator.ValidateShareRoot(shareRoot);
        var files = new List<RemoteFileDescriptor>();

        foreach (var path in Directory.EnumerateFiles(validatedRoot, "*", SearchOption.AllDirectories).OrderBy(static value => value, StringComparer.OrdinalIgnoreCase))
        {
            cancellationToken.ThrowIfCancellationRequested();
            var info = new FileInfo(path);
            await using var stream = info.Open(FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
            var hash = await SHA256.HashDataAsync(stream, cancellationToken);
            var relativePath = Path.GetRelativePath(validatedRoot, path).Replace('\\', '/');
            files.Add(new RemoteFileDescriptor(
                Id: relativePath.ToLowerInvariant(),
                RelativePath: relativePath,
                Name: info.Name,
                FileExtension: string.IsNullOrWhiteSpace(info.Extension) ? null : info.Extension.TrimStart('.'),
                ByteSize: info.Length,
                CreatedAt: info.CreationTimeUtc == DateTime.MinValue ? null : info.CreationTimeUtc,
                ModifiedAt: info.LastWriteTimeUtc,
                ContentHash: Convert.ToHexString(hash).ToLowerInvariant(),
                MimeType: MimeTypeFor(info.Extension),
                IsEligible: true,
                LogicalGrouping: Path.GetDirectoryName(relativePath)?.Replace('\\', '/')));
        }

        return new RemoteFileManifest(deviceId, DateTimeOffset.UtcNow, files);
    }

    private static string? MimeTypeFor(string extension) => extension.ToLowerInvariant() switch
    {
        ".jpg" or ".jpeg" => "image/jpeg",
        ".png" => "image/png",
        ".pdf" => "application/pdf",
        ".txt" => "text/plain",
        ".csv" => "text/csv",
        ".json" => "application/json",
        _ => null,
    };
}

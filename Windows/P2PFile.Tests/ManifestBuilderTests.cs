using P2PFile.Infrastructure;

namespace P2PFile.Tests;

public sealed class ManifestBuilderTests
{
    [Fact]
    public async Task BuildsRelativeManifestEntries()
    {
        var root = Path.Combine(Path.GetTempPath(), Path.GetRandomFileName());
        Directory.CreateDirectory(Path.Combine(root, "Specs"));
        await File.WriteAllTextAsync(Path.Combine(root, "Specs", "sample.txt"), "hello world");

        try
        {
            var builder = new ManifestBuilder(new ShareRootValidator());
            var manifest = await builder.BuildAsync(Guid.NewGuid(), root, CancellationToken.None);
            var file = Assert.Single(manifest.Files);
            Assert.Equal("Specs/sample.txt", file.RelativePath);
            Assert.Equal("sample.txt", file.Name);
        }
        finally
        {
            Directory.Delete(root, recursive: true);
        }
    }
}

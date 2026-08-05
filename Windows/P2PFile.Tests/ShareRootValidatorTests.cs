using P2PFile.Infrastructure;

namespace P2PFile.Tests;

public sealed class ShareRootValidatorTests
{
    [Fact]
    public void RejectsPathTraversal()
    {
        var root = Path.Combine(Path.GetTempPath(), Path.GetRandomFileName());
        Directory.CreateDirectory(root);
        var validator = new ShareRootValidator();

        try
        {
            Assert.Throws<InvalidOperationException>(() => validator.ResolveRelativePath(root, "../secrets.txt"));
        }
        finally
        {
            Directory.Delete(root, recursive: true);
        }
    }
}

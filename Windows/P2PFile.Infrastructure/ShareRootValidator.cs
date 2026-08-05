namespace P2PFile.Infrastructure;

public sealed class ShareRootValidator
{
    public string ValidateShareRoot(string path)
    {
        if (string.IsNullOrWhiteSpace(path))
        {
            throw new InvalidOperationException("The share root cannot be empty.");
        }

        var fullPath = Path.GetFullPath(path);
        if (!Directory.Exists(fullPath))
        {
            throw new DirectoryNotFoundException($"The share root does not exist: {fullPath}");
        }

        if (Path.GetPathRoot(fullPath)?.Equals(fullPath, StringComparison.OrdinalIgnoreCase) == true)
        {
            throw new InvalidOperationException("The root of a system drive cannot be shared.");
        }

        if (OperatingSystem.IsWindows())
        {
            var protectedRoots = new[]
            {
                Environment.GetFolderPath(Environment.SpecialFolder.Windows),
                Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles),
            }
            .Where(static value => !string.IsNullOrWhiteSpace(value))
            .Select(Path.GetFullPath);

            if (protectedRoots.Any(root => fullPath.StartsWith(root, StringComparison.OrdinalIgnoreCase)))
            {
                throw new InvalidOperationException("Protected Windows directories cannot be shared.");
            }
        }

        return fullPath;
    }

    public string ResolveRelativePath(string shareRoot, string relativePath)
    {
        var normalized = relativePath.Replace('\\', '/');
        var segments = normalized.Split('/', StringSplitOptions.RemoveEmptyEntries);
        if (segments.Any(segment => segment is "." or ".."))
        {
            throw new InvalidOperationException("Path traversal was detected.");
        }

        var resolved = Path.GetFullPath(Path.Combine(shareRoot, Path.Combine(segments)));
        var validatedRoot = Path.GetFullPath(shareRoot);
        if (!resolved.StartsWith(validatedRoot, StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidOperationException("The requested path escapes the configured share root.");
        }

        return resolved;
    }
}

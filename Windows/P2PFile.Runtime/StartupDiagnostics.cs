using System.Text;

namespace P2PFile.Runtime;

public sealed class StartupDiagnostics
{
    public StartupDiagnostics(string stateRoot)
    {
        StateRoot = Path.GetFullPath(Environment.ExpandEnvironmentVariables(stateRoot));
    }

    public string StateRoot { get; }

    public string LogFilePath => GetLogFilePath(StateRoot);

    public void Clear()
    {
        try
        {
            if (File.Exists(LogFilePath))
            {
                File.Delete(LogFilePath);
            }
        }
        catch
        {
        }
    }

    public void Write(string context, Exception? exception = null)
    {
        try
        {
            Directory.CreateDirectory(StateRoot);

            var builder = new StringBuilder();
            builder.AppendLine($"[{DateTimeOffset.Now:yyyy-MM-dd HH:mm:ss zzz}] {context}");
            if (exception is not null)
            {
                builder.AppendLine(exception.ToString());
            }
            builder.AppendLine();

            File.AppendAllText(LogFilePath, builder.ToString());
        }
        catch
        {
        }
    }

    public static string GetLogFilePath(string stateRoot)
    {
        return Path.Combine(
            Path.GetFullPath(Environment.ExpandEnvironmentVariables(stateRoot)),
            "startup-error.log");
    }
}

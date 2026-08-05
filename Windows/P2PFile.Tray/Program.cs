using P2PFile.Runtime;

namespace P2PFile.Tray;

internal static class Program
{
    private static readonly P2PFileRuntimeHostOptions RuntimeOptions = P2PFileReferenceRuntimeHost.Create();

    [STAThread]
    private static void Main()
    {
        ApplicationConfiguration.Initialize();
        using var runtime = TryStartRuntime(RuntimeOptions);
        if (runtime is null)
        {
            return;
        }

        var runAtLoginManager = RunAtLoginManager.CreateDefault(RuntimeOptions);
        runAtLoginManager.PromptIfNeeded();

        Application.Run(new TrayApplicationContext(runtime, runAtLoginManager));
    }

    private static TrayRuntimeSession? TryStartRuntime(P2PFileRuntimeHostOptions runtimeOptions)
    {
        try
        {
            return TrayRuntimeSession.Start(runtimeOptions);
        }
        catch (Exception ex)
        {
            MessageBox.Show(
                $"P2P File Tray could not connect to the local runtime or start its embedded endpoint.{Environment.NewLine}{Environment.NewLine}{ex.Message}{Environment.NewLine}{Environment.NewLine}If the problem persists, check:{Environment.NewLine}{StartupDiagnostics.GetLogFilePath(runtimeOptions.StateRoot)}",
                "P2P File Sharing",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error);
            return null;
        }
    }
}

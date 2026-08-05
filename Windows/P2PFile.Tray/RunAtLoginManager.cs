using Microsoft.Win32;
using P2PFile.Runtime;

namespace P2PFile.Tray;

internal sealed class RunAtLoginManager
{
    private const string RunKeyPath = @"Software\Microsoft\Windows\CurrentVersion\Run";

    private readonly string _executablePath;
    private readonly TrayPreferencesStore _preferencesStore;
    private readonly string _runValueName;

    public RunAtLoginManager(string executablePath, TrayPreferencesStore preferencesStore, string runValueName)
    {
        _executablePath = executablePath;
        _preferencesStore = preferencesStore;
        _runValueName = runValueName;
    }

    public static RunAtLoginManager CreateDefault(P2PFileRuntimeHostOptions runtimeOptions)
    {
        ArgumentNullException.ThrowIfNull(runtimeOptions);

        return new RunAtLoginManager(
            Application.ExecutablePath,
            new TrayPreferencesStore(runtimeOptions),
            runtimeOptions.ControlPipeName);
    }

    public bool IsEnabled()
    {
        using var key = Registry.CurrentUser.OpenSubKey(RunKeyPath, writable: false);
        var value = key?.GetValue(_runValueName) as string;
        return string.Equals(NormalizeCommand(value), NormalizeCommand(GetCommand()), StringComparison.OrdinalIgnoreCase);
    }

    public void SetEnabled(bool enabled)
    {
        using var key = Registry.CurrentUser.CreateSubKey(RunKeyPath)
            ?? throw new InvalidOperationException("The current user's startup registry key is unavailable.");

        if (enabled)
        {
            key.SetValue(_runValueName, GetCommand(), RegistryValueKind.String);
        }
        else
        {
            key.DeleteValue(_runValueName, throwOnMissingValue: false);
        }

        SavePreferences(_preferencesStore.Load() with { HasPromptedForRunAtLogin = true });
    }

    public void PromptIfNeeded(IWin32Window? owner = null)
    {
        var preferences = _preferencesStore.Load();
        if (preferences.HasPromptedForRunAtLogin)
        {
            return;
        }

        if (IsEnabled())
        {
            SavePreferences(preferences with { HasPromptedForRunAtLogin = true });
            return;
        }

        var result = MessageBox.Show(
            owner,
            $"Launch P2P File Sharing automatically when you sign in to Windows?{Environment.NewLine}{Environment.NewLine}You can change this later from the tray menu.",
            "P2P File Sharing",
            MessageBoxButtons.YesNo,
            MessageBoxIcon.Question);

        if (result == DialogResult.Yes)
        {
            try
            {
                SetEnabled(true);
                return;
            }
            catch (Exception ex)
            {
                SavePreferences(preferences with { HasPromptedForRunAtLogin = true });
                MessageBox.Show(
                    owner,
                    $"P2P File Sharing could not enable launch at sign-in.{Environment.NewLine}{Environment.NewLine}{ex.Message}",
                    "P2P File Sharing",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Warning);
                return;
            }
        }

        SavePreferences(preferences with { HasPromptedForRunAtLogin = true });
    }

    private string GetCommand()
    {
        return $"\"{_executablePath}\"";
    }

    private void SavePreferences(TrayPreferences preferences)
    {
        _preferencesStore.Save(preferences);
    }

    private static string? NormalizeCommand(string? command)
    {
        return string.IsNullOrWhiteSpace(command) ? null : command.Trim();
    }
}

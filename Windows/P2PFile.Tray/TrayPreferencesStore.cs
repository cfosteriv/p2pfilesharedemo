using System.Text.Json;
using P2PFile.Runtime;

namespace P2PFile.Tray;

internal sealed class TrayPreferencesStore
{
    private static readonly JsonSerializerOptions SerializerOptions = new()
    {
        WriteIndented = true,
    };

    private readonly string _filePath;

    public TrayPreferencesStore(P2PFileRuntimeHostOptions runtimeOptions, string? filePath = null)
    {
        ArgumentNullException.ThrowIfNull(runtimeOptions);

        _filePath = filePath ?? Path.Combine(runtimeOptions.StateRoot, "tray-preferences.json");
    }

    public TrayPreferences Load()
    {
        try
        {
            if (!File.Exists(_filePath))
            {
                return TrayPreferences.Default;
            }

            using var stream = File.OpenRead(_filePath);
            return JsonSerializer.Deserialize<TrayPreferences>(stream, SerializerOptions) ?? TrayPreferences.Default;
        }
        catch (Exception)
        {
            return TrayPreferences.Default;
        }
    }

    public void Save(TrayPreferences preferences)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(_filePath)!);

        using var stream = File.Create(_filePath);
        JsonSerializer.Serialize(stream, preferences, SerializerOptions);
    }
}

internal sealed record TrayPreferences(bool HasPromptedForRunAtLogin)
{
    public static TrayPreferences Default { get; } = new(false);
}

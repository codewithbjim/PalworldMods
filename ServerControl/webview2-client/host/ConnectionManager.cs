using System.Text.Json;
using System.Text.Json.Serialization.Metadata;

namespace PalworldServerControl.Host;

internal sealed class ConnectionManager
{
    internal const string DefaultShareRoot = @"C:\PalServer";
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web)
    {
        WriteIndented = true,
        TypeInfoResolver = new DefaultJsonTypeInfoResolver()
    };
    private readonly string _settingsPath;
    private readonly string? _explicitRoot;

    internal ConnectionManager(string? explicitRoot, string? settingsPath = null)
    {
        _explicitRoot = NormalizeOptional(explicitRoot);
        _settingsPath = settingsPath ?? Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "virtualbjorn", "PalworldServerControl", "connection.json");
    }

    internal string ResolveInitialRoot()
    {
        if (_explicitRoot is not null) return _explicitRoot;
        var saved = ReadSavedRoot();
        if (saved is not null) return saved;
        return DetectLocalRoot() ?? DefaultShareRoot;
    }

    internal ConnectionState Inspect(string path, string source)
    {
        try
        {
            var root = Normalize(path);
            if (!Directory.Exists(root)) return new(root, source, false, "The folder cannot be reached.");
            var active = Path.Combine(root, "Pal", "Saved", "Config", "WindowsServer", "PalWorldSettings.ini");
            var defaults = Path.Combine(root, "DefaultPalWorldSettings.ini");
            if (!File.Exists(active)) return new(root, source, false, "PalWorldSettings.ini was not found under Pal\\Saved\\Config\\WindowsServer.");
            if (!File.Exists(defaults)) return new(root, source, false, "DefaultPalWorldSettings.ini was not found in the selected server folder.");
            return new(root, source, true, "Palworld server configuration found.");
        }
        catch (Exception exception) when (exception is ArgumentException or IOException or UnauthorizedAccessException or NotSupportedException)
        {
            return new(path.Trim(), source, false, exception.Message);
        }
    }

    internal ConnectionState InspectCurrent(string path) => Inspect(path, GetSource(path));

    internal string? DetectLocalRoot()
    {
        var executable = Environment.ProcessPath;
        if (string.IsNullOrWhiteSpace(executable)) return null;
        var directory = Path.GetDirectoryName(executable);
        if (directory is null) return null;
        for (var current = new DirectoryInfo(directory); current is not null; current = current.Parent)
        {
            if (Inspect(current.FullName, "Detected on this machine").Valid) return current.FullName;
            if (current.Parent is null || current.Parent.Parent is null) break;
        }
        return null;
    }

    internal void Save(string path)
    {
        var root = Normalize(path);
        Directory.CreateDirectory(Path.GetDirectoryName(_settingsPath)!);
        var temporary = _settingsPath + ".tmp";
        File.WriteAllText(temporary, JsonSerializer.Serialize(new SavedConnection(root), JsonOptions));
        File.Move(temporary, _settingsPath, true);
    }

    private string? ReadSavedRoot()
    {
        try
        {
            if (!File.Exists(_settingsPath)) return null;
            return NormalizeOptional(JsonSerializer.Deserialize<SavedConnection>(File.ReadAllText(_settingsPath), JsonOptions)?.Path);
        }
        catch (Exception exception) when (exception is JsonException or IOException or UnauthorizedAccessException or ArgumentException or NotSupportedException)
        {
            return null;
        }
    }

    private string GetSource(string path)
    {
        var normalized = Normalize(path);
        if (_explicitRoot is not null && PathEquals(normalized, _explicitRoot)) return "Command line";
        var saved = ReadSavedRoot();
        if (saved is not null && PathEquals(normalized, saved)) return "Remembered";
        var detected = DetectLocalRoot();
        if (detected is not null && PathEquals(normalized, detected)) return "Detected on this machine";
        return normalized.StartsWith(@"\\", StringComparison.Ordinal) ? "Network share" : "Selected folder";
    }

    private static bool PathEquals(string left, string right) =>
        string.Equals(left.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar), right.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar), StringComparison.OrdinalIgnoreCase);

    private static string? NormalizeOptional(string? path) => string.IsNullOrWhiteSpace(path) ? null : Normalize(path);
    private static string Normalize(string path)
    {
        if (string.IsNullOrWhiteSpace(path)) throw new ArgumentException("Enter or choose a server folder.");
        return Path.GetFullPath(path.Trim().Trim('"'));
    }

    private sealed record SavedConnection(string Path);
}

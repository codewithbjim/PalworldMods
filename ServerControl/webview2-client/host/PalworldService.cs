using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.Json.Serialization.Metadata;

namespace PalworldServerControl.Host;

internal sealed class PalworldService
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web)
    {
        WriteIndented = true,
        TypeInfoResolver = new DefaultJsonTypeInfoResolver()
    };
    private static readonly HashSet<string> AllowedCommands = new(StringComparer.Ordinal) { "start", "stop", "restart", "status" };
    private readonly string _shareRoot;
    private readonly string _metadataRoot;

    internal PalworldService(string shareRoot, string metadataRoot)
    {
        _shareRoot = Path.GetFullPath(shareRoot);
        _metadataRoot = metadataRoot;
    }

    internal async Task<ServerSnapshot> LoadSnapshotAsync()
    {
        var paths = GetPaths();
        var metadataTask = ReadMetadataAsync();
        var activeBytesTask = File.ReadAllBytesAsync(paths.Active);
        var defaultContentTask = File.ReadAllTextAsync(paths.Defaults);
        var statusTask = ReadStatusAsync(paths.Status);
        await Task.WhenAll(metadataTask, activeBytesTask, defaultContentTask, statusTask);
        var activeBytes = await activeBytesTask;
        var activeContent = DecodeUtf8(activeBytes);
        var active = PalConfig.Read(activeContent);
        var defaults = PalConfig.Read(await defaultContentTask);
        var startupExists = File.Exists(paths.Startup);
        var startupBytes = startupExists ? await File.ReadAllBytesAsync(paths.Startup) : null;
        var startup = startupBytes is null
            ? new JsonObject()
            : JsonNode.Parse(DecodeUtf8(startupBytes))?.AsObject() ?? new JsonObject();
        var settings = new List<SettingView>();

        foreach (var item in await metadataTask)
        {
            if (item.Source == "ini")
            {
                if (!active.Entries.TryGetValue(item.Name, out var rawValue) || !defaults.Entries.TryGetValue(item.Name, out var rawDefault))
                    throw new InvalidOperationException($"Configuration is missing {item.Name}.");
                var value = PalConfig.Decode(rawValue, item.Type);
                var defaultValue = PalConfig.Decode(rawDefault, item.Type);
                var secret = item.Type == "secret";
                settings.Add(ToView(item, secret ? "" : PalConfig.Display(value, item), secret ? "" : PalConfig.Display(defaultValue, item),
                    value == defaultValue, secret ? value.Length > 0 : null));
            }
            else
            {
                var raw = startup[item.Name];
                var value = raw is null ? DefaultText(item) : NodeText(raw, item.Type);
                var defaultValue = DefaultText(item);
                settings.Add(ToView(item, value, defaultValue, value == defaultValue, null));
            }
        }

        return new ServerSnapshot(_shareRoot, await statusTask, settings, PalConfig.Sha256(activeBytes),
            startupBytes is null ? null : PalConfig.Sha256(startupBytes));
    }

    internal async Task<SaveResult> SaveSettingsAsync(SaveRequest request)
    {
        if (request.Changes is null || string.IsNullOrWhiteSpace(request.ExpectedIniHash))
            throw new InvalidOperationException("Invalid save request.");
        var paths = GetPaths();
        var metadata = await ReadMetadataAsync();
        var byKey = metadata.ToDictionary(item => $"{item.Source}::{item.Name}", StringComparer.Ordinal);
        var iniChanges = new Dictionary<string, string>(StringComparer.Ordinal);
        var startupChanges = new Dictionary<string, object?>(StringComparer.Ordinal);
        foreach (var (key, value) in request.Changes)
        {
            if (!byKey.TryGetValue(key, out var setting)) throw new InvalidOperationException($"Unknown setting: {key}");
            var encoded = PalConfig.Encode(value, setting);
            if (setting.Source == "ini") iniChanges.Add(setting.Name, encoded);
            else startupChanges.Add(setting.Name, setting.Type switch
            {
                "boolean" => encoded == "True",
                "integer" => long.Parse(encoded, System.Globalization.CultureInfo.InvariantCulture),
                "string" or "raw" => value,
                _ => encoded
            });
        }

        var backups = new List<string>();
        if (iniChanges.Count > 0)
        {
            var currentBytes = await File.ReadAllBytesAsync(paths.Active);
            if (!PalConfig.Sha256(currentBytes).Equals(request.ExpectedIniHash, StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("PalWorldSettings.ini changed after it was loaded. Reload before saving.");
            var output = PalConfig.Write(PalConfig.Read(DecodeUtf8(currentBytes)), iniChanges);
            var backup = await ReplaceWithBackupAsync(paths.Active, output, request.ExpectedIniHash);
            if (backup is not null) backups.Add(backup);
        }
        if (startupChanges.Count > 0)
        {
            var currentBytes = File.Exists(paths.Startup) ? await File.ReadAllBytesAsync(paths.Startup) : null;
            var current = currentBytes is null ? new JsonObject() : JsonNode.Parse(DecodeUtf8(currentBytes))?.AsObject() ?? new JsonObject();
            foreach (var item in metadata.Where(candidate => candidate.Source == "startup"))
            {
                if (startupChanges.TryGetValue(item.Name, out var changed)) current[item.Name] = JsonValue.Create(changed);
                else if (!current.ContainsKey(item.Name)) current[item.Name] = JsonNode.Parse(item.Default.GetRawText());
            }
            current["version"] = 1;
            if (!current.ContainsKey("additionalArguments")) current["additionalArguments"] = "";
            var output = current.ToJsonString(JsonOptions) + Environment.NewLine;
            var backup = await ReplaceWithBackupAsync(paths.Startup, output, request.ExpectedStartupHash);
            if (backup is not null) backups.Add(backup);
        }
        return new SaveResult(iniChanges.Count + startupChanges.Count, backups);
    }

    internal async Task<string> SendCommandAsync(CommandRequest request)
    {
        if (!AllowedCommands.Contains(request.Command)) throw new InvalidOperationException("Unsupported server command.");
        var paths = GetPaths();
        if (!Directory.Exists(paths.RequestRoot)) throw new DirectoryNotFoundException("The server request directory is unavailable.");
        var id = Guid.NewGuid().ToString("N");
        var temporary = Path.Combine(paths.RequestRoot, id + ".tmp");
        var destination = Path.Combine(paths.RequestRoot, id + ".json");
        var payload = JsonSerializer.Serialize(new
        {
            version = 1, id, command = request.Command, requestedAtUtc = DateTimeOffset.UtcNow,
            requestedBy = Environment.UserName.Length == 0 ? "WebView2 client" : Environment.UserName
        }, JsonOptions) + Environment.NewLine;
        await File.WriteAllTextAsync(temporary, payload, new UTF8Encoding(false));
        File.Move(temporary, destination);
        return id;
    }

    private async Task<IReadOnlyList<SettingMetadata>> ReadMetadataAsync()
    {
        var result = new List<SettingMetadata>();
        foreach (var (fileName, source) in new[] { ("PalServerSettings.json", "ini"), ("PalServerStartupSettings.json", "startup") })
        {
            using var document = JsonDocument.Parse(await File.ReadAllBytesAsync(Path.Combine(_metadataRoot, fileName)));
            foreach (var value in document.RootElement.EnumerateArray())
            {
                result.Add(new SettingMetadata(
                    value.GetProperty("name").GetString()!, value.GetProperty("category").GetString()!, value.GetProperty("label").GetString()!,
                    value.GetProperty("description").GetString()!, value.GetProperty("type").GetString()!,
                    value.TryGetProperty("default", out var defaultValue) ? defaultValue.Clone() : default,
                    value.TryGetProperty("min", out var min) ? min.GetDouble() : null,
                    value.TryGetProperty("max", out var max) ? max.GetDouble() : null,
                    value.TryGetProperty("options", out var options) ? options.EnumerateArray().Select(option => option.GetString()!).ToArray() : null,
                    source));
            }
        }
        return result;
    }

    private static SettingView ToView(SettingMetadata item, string value, string defaultValue, bool isDefault, bool? hasSecret) =>
        new(item.Name, item.Category, item.Label, item.Description, item.Type,
            item.Default.ValueKind == JsonValueKind.Undefined ? null : item.Default.Clone(),
            item.Min, item.Max, item.Options, item.Source, $"{item.Source}::{item.Name}", value, defaultValue, isDefault, hasSecret);

    private static string DefaultText(SettingMetadata item) => item.Default.ValueKind switch
    {
        JsonValueKind.True => "True", JsonValueKind.False => "False", JsonValueKind.String => item.Default.GetString() ?? "",
        JsonValueKind.Undefined => "", _ => item.Default.GetRawText()
    };

    private static string NodeText(JsonNode node, string type) => type == "boolean"
        ? (node.GetValue<bool>() ? "True" : "False")
        : node.ToString();

    private static async Task<ServerStatus> ReadStatusAsync(string path)
    {
        try
        {
            return ParseStatus(await File.ReadAllBytesAsync(path), DateTimeOffset.UtcNow);
        }
        catch { return new("Unavailable", "The server helper is not reporting."); }
    }

    internal static ServerStatus ParseStatus(byte[] bytes, DateTimeOffset now)
    {
        using var document = JsonDocument.Parse(DecodeUtf8(bytes));
        var root = document.RootElement;
        if (!root.TryGetProperty("updatedAtUtc", out var updated) ||
            now - updated.GetDateTimeOffset() > TimeSpan.FromSeconds(10))
            return new("Unavailable", "The server helper is not reporting. It may be stopped.");
        return new(
            root.GetProperty("state").GetString() ?? "Unknown",
            root.GetProperty("detail").GetString() ?? "",
            OptionalInt(root, "currentPlayers"), OptionalInt(root, "maxPlayers"),
            OptionalLong(root, "uptimeSeconds"), OptionalDouble(root, "serverFps"));
    }

    private static int? OptionalInt(JsonElement root, string name) => root.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.Number ? value.GetInt32() : null;
    private static long? OptionalLong(JsonElement root, string name) => root.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.Number ? value.GetInt64() : null;
    private static double? OptionalDouble(JsonElement root, string name) => root.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.Number ? value.GetDouble() : null;

    private static string DecodeUtf8(byte[] bytes)
    {
        var offset = bytes.Length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF ? 3 : 0;
        return new UTF8Encoding(false, true).GetString(bytes, offset, bytes.Length - offset);
    }

    private static async Task<string?> ReplaceWithBackupAsync(string path, string content, string? expectedHash)
    {
        var exists = File.Exists(path);
        if (exists)
        {
            var current = await File.ReadAllBytesAsync(path);
            if (expectedHash is null || !PalConfig.Sha256(current).Equals(expectedHash, StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException($"{Path.GetFileName(path)} changed after it was loaded. Reload before saving.");
        }
        else if (expectedHash is not null) throw new InvalidOperationException($"{Path.GetFileName(path)} was removed after it was loaded.");

        var timestamp = DateTimeOffset.UtcNow.ToString("yyyyMMdd'T'HHmmssfff'Z'");
        var backup = exists ? $"{path}.backup-webview2-{timestamp}" : null;
        var temporary = $"{path}.tmp-{Guid.NewGuid():N}";
        await File.WriteAllTextAsync(temporary, content, new UTF8Encoding(false));
        try
        {
            if (backup is not null) File.Copy(path, backup);
            File.Move(temporary, path, true);
        }
        catch
        {
            try { File.Delete(temporary); } catch { }
            throw;
        }
        return backup;
    }

    private Paths GetPaths()
    {
        var control = Path.Combine(_shareRoot, "ServerControl");
        return new(_shareRoot, Path.Combine(control, "requests"), Path.Combine(control, "status.json"),
            Path.Combine(control, "startup-settings.json"),
            Path.Combine(_shareRoot, "Pal", "Saved", "Config", "WindowsServer", "PalWorldSettings.ini"),
            Path.Combine(_shareRoot, "DefaultPalWorldSettings.ini"));
    }

    private sealed record Paths(string ShareRoot, string RequestRoot, string Status, string Startup, string Active, string Defaults);
}

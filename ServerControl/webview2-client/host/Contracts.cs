using System.Text.Json;
using System.Text.Json.Serialization;

namespace PalworldServerControl.Host;

internal sealed record BridgeRequest(string Id, string Method, JsonElement Params);
internal sealed record BridgeResponse(string Id, bool Ok, object? Result, string? Error);
internal sealed record CommandRequest(string Command);
internal sealed record SaveRequest(Dictionary<string, string> Changes, string ExpectedIniHash, string? ExpectedStartupHash);
internal sealed record SaveResult(int Changed, IReadOnlyList<string> Backups);
internal sealed record ConnectionRequest(string Path, bool Remember = true);
internal sealed record ConnectionState(string Path, string Source, bool Valid, string Detail);
internal sealed record HelperState(bool Installed, bool CanInstall, string Detail);

internal sealed record SettingMetadata(
    string Name, string Category, string Label, string Description, string Type,
    JsonElement Default, double? Min, double? Max, string[]? Options, string Source);

internal sealed record SettingView(
    string Name, string Category, string Label, string Description, string Type,
    [property: JsonPropertyName("default")] object? DefaultMetadata,
    double? Min, double? Max, string[]? Options, string Source, string Key,
    string Value, string DefaultValue, bool IsDefault, bool? HasSecret = null);

internal sealed record ServerStatus(
    string State, string Detail, int? CurrentPlayers = null, int? MaxPlayers = null,
    long? UptimeSeconds = null, double? ServerFps = null);

internal sealed record ServerSnapshot(
    string ShareRoot, ServerStatus Status, IReadOnlyList<SettingView> Settings,
    string IniHash, string? StartupHash);

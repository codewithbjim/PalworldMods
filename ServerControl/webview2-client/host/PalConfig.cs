using System.Globalization;
using System.Security.Cryptography;
using System.Text;

namespace PalworldServerControl.Host;

internal sealed record PalDocument(string Prefix, string Suffix, Dictionary<string, string> Entries, List<string> Order);

internal static class PalConfig
{
    internal static IReadOnlyList<string> SplitOptionSegments(string text)
    {
        var result = new List<string>();
        var start = 0;
        var depth = 0;
        var quoted = false;
        for (var index = 0; index < text.Length; index++)
        {
            var character = text[index];
            if (character == '"')
            {
                var slashes = 0;
                for (var behind = index - 1; behind >= 0 && text[behind] == '\\'; behind--) slashes++;
                if (slashes % 2 == 0) quoted = !quoted;
                continue;
            }
            if (quoted) continue;
            if (character == '(') depth++;
            else if (character == ')') depth--;
            else if (character == ',' && depth == 0)
            {
                result.Add(text[start..index]);
                start = index + 1;
            }
        }
        result.Add(text[start..]);
        return result;
    }

    internal static PalDocument Read(string content)
    {
        const string marker = "OptionSettings=(";
        var markerIndex = content.IndexOf(marker, StringComparison.Ordinal);
        if (markerIndex < 0) throw new InvalidOperationException("OptionSettings section was not found.");
        var innerStart = markerIndex + marker.Length;
        var depth = 1;
        var quoted = false;
        var innerEnd = -1;
        for (var index = innerStart; index < content.Length; index++)
        {
            var character = content[index];
            if (character == '"')
            {
                var slashes = 0;
                for (var behind = index - 1; behind >= 0 && content[behind] == '\\'; behind--) slashes++;
                if (slashes % 2 == 0) quoted = !quoted;
                continue;
            }
            if (quoted) continue;
            if (character == '(') depth++;
            else if (character == ')' && --depth == 0) { innerEnd = index; break; }
        }
        if (innerEnd < 0) throw new InvalidOperationException("OptionSettings closing parenthesis was not found.");

        var entries = new Dictionary<string, string>(StringComparer.Ordinal);
        var order = new List<string>();
        foreach (var segment in SplitOptionSegments(content[innerStart..innerEnd]))
        {
            var equals = segment.IndexOf('=');
            if (equals <= 0) throw new InvalidOperationException($"Invalid OptionSettings segment: {segment}");
            var name = segment[..equals].Trim();
            if (name.Length == 0 || !(char.IsAsciiLetter(name[0]) || name[0] == '_') ||
                name.Any(character => !(char.IsAsciiLetterOrDigit(character) || character == '_')))
                throw new InvalidOperationException($"Invalid setting name: {name}");
            if (!entries.TryAdd(name, segment[(equals + 1)..]))
                throw new InvalidOperationException($"Duplicate setting found: {name}");
            order.Add(name);
        }
        return new PalDocument(content[..innerStart], content[innerEnd..], entries, order);
    }

    internal static string Write(PalDocument document, IReadOnlyDictionary<string, string> changes)
    {
        foreach (var name in changes.Keys)
            if (!document.Entries.ContainsKey(name)) throw new InvalidOperationException($"Cannot update missing setting: {name}");
        return document.Prefix + string.Join(',', document.Order.Select(name =>
            $"{name}={(changes.TryGetValue(name, out var value) ? value : document.Entries[name])}")) + document.Suffix;
    }

    internal static string Decode(string rawValue, string type) =>
        type is "string" or "secret" ? Unquote(rawValue) : rawValue;

    internal static string Encode(string value, SettingMetadata metadata)
    {
        switch (metadata.Type)
        {
            case "boolean":
                if (!bool.TryParse(value, out var boolean)) throw new InvalidOperationException($"{metadata.Name} must be True or False.");
                return boolean ? "True" : "False";
            case "integer":
                if (!long.TryParse(value.Trim(), NumberStyles.AllowLeadingSign, CultureInfo.InvariantCulture, out var integer))
                    throw new InvalidOperationException($"{metadata.Name} must be a whole number.");
                ValidateRange(integer, metadata);
                return integer.ToString(CultureInfo.InvariantCulture);
            case "number":
                if (string.IsNullOrWhiteSpace(value) || !double.TryParse(value, NumberStyles.Float, CultureInfo.InvariantCulture, out var number) || !double.IsFinite(number))
                    throw new InvalidOperationException($"{metadata.Name} must be a finite number.");
                ValidateRange(number, metadata);
                return TrimNumber(number);
            case "enum":
                var option = metadata.Options?.FirstOrDefault(candidate => string.Equals(candidate, value, StringComparison.OrdinalIgnoreCase));
                return option ?? throw new InvalidOperationException($"{metadata.Name} must be one of: {string.Join(", ", metadata.Options ?? [])}.");
            case "string":
            case "secret":
                return $"\"{value.Replace("\\", "\\\\", StringComparison.Ordinal).Replace("\"", "\\\"", StringComparison.Ordinal)}\"";
            case "raw": return value;
            default: throw new InvalidOperationException($"Unsupported setting type: {metadata.Type}");
        }
    }

    internal static string Display(string value, SettingMetadata metadata) =>
        metadata.Type == "number" && double.TryParse(value, NumberStyles.Float, CultureInfo.InvariantCulture, out var number)
            ? TrimNumber(number) : value;

    internal static string Sha256(byte[] content) => Convert.ToHexString(SHA256.HashData(content));
    internal static string Sha256(string content) => Sha256(Encoding.UTF8.GetBytes(content));

    private static string Unquote(string value) => value.Length >= 2 && value[0] == '"' && value[^1] == '"'
        ? value[1..^1].Replace("\\\"", "\"", StringComparison.Ordinal).Replace("\\\\", "\\", StringComparison.Ordinal)
        : value;

    private static string TrimNumber(double value) => value.ToString("0.######", CultureInfo.InvariantCulture);

    private static void ValidateRange(double value, SettingMetadata metadata)
    {
        if (metadata.Min is not null && value < metadata.Min) throw new InvalidOperationException($"{metadata.Name} must be at least {metadata.Min}.");
        if (metadata.Max is not null && value > metadata.Max) throw new InvalidOperationException($"{metadata.Name} must be at most {metadata.Max}.");
    }
}

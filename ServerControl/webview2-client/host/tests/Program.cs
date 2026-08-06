using System.Text.Json;
using PalworldServerControl.Host;

var tests = new (string Name, Action Run)[]
{
    ("quoted commas and nested tuples round-trip exactly", () =>
    {
        const string input = "[/Script/Pal.PalGameWorldSettings]\r\nOptionSettings=(ServerName=\"Operator, \\\"North\\\"\",BanListURL=\"https://example.test/a,b\",Struct=(Outer=(Value=1,Text=\"x,y\")),UnknownFuture=(A=1,B=(C=2)))\r\n;tail\r\n";
        var document = PalConfig.Read(input);
        Equal(input, PalConfig.Write(document, new Dictionary<string, string>()));
        Equal("\"Operator, \\\"North\\\"\"", document.Entries["ServerName"]);
        Equal("(Outer=(Value=1,Text=\"x,y\"))", document.Entries["Struct"]);
    }),
    ("one edit preserves unknown values and surrounding bytes", () =>
    {
        const string input = "header\nOptionSettings=(Known=True,Unknown=(One=\"a,b\",Two=(X=3)),Tail=\"z\")\nfooter";
        const string expected = "header\nOptionSettings=(Known=False,Unknown=(One=\"a,b\",Two=(X=3)),Tail=\"z\")\nfooter";
        Equal(expected, PalConfig.Write(PalConfig.Read(input), new Dictionary<string, string> { ["Known"] = "False" }));
    }),
    ("Boolean accepts only dropdown choices", () =>
    {
        var metadata = Metadata("bEnabled", "boolean");
        Equal("True", PalConfig.Encode("true", metadata));
        Equal("False", PalConfig.Encode("FALSE", metadata));
        Throws(() => PalConfig.Encode("1", metadata));
        Throws(() => PalConfig.Encode("yes", metadata));
    }),
    ("enum canonicalizes a dropdown choice and rejects free text", () =>
    {
        var metadata = Metadata("Mode", "enum", ["None", "Region", "All"]);
        Equal("Region", PalConfig.Encode("region", metadata));
        Throws(() => PalConfig.Encode("PerRegion", metadata));
    }),
    ("string escaping is reversible", () =>
    {
        var metadata = Metadata("Name", "string");
        const string value = "path\\name, \\\"quoted\\\"";
        var encoded = PalConfig.Encode(value, metadata);
        Equal(value, PalConfig.Decode(encoded, "string"));
    }),
    ("connection validation recognizes a Palworld server root", () =>
    {
        var root = Path.Combine(Path.GetTempPath(), "PalworldServerControlTests", Guid.NewGuid().ToString("N"));
        try
        {
            Directory.CreateDirectory(Path.Combine(root, "Pal", "Saved", "Config", "WindowsServer"));
            File.WriteAllText(Path.Combine(root, "Pal", "Saved", "Config", "WindowsServer", "PalWorldSettings.ini"), "test");
            File.WriteAllText(Path.Combine(root, "DefaultPalWorldSettings.ini"), "test");
            var manager = new ConnectionManager(null, Path.Combine(root, "state", "connection.json"));
            var state = manager.Inspect(root, "Test");
            Equal(true, state.Valid);
            manager.Save(root);
            Equal(Path.GetFullPath(root), manager.ResolveInitialRoot());
        }
        finally { if (Directory.Exists(root)) Directory.Delete(root, true); }
    }),
    ("connection validation rejects an unrelated folder", () =>
    {
        var root = Path.Combine(Path.GetTempPath(), "PalworldServerControlTests", Guid.NewGuid().ToString("N"));
        try
        {
            Directory.CreateDirectory(root);
            var manager = new ConnectionManager(null, Path.Combine(root, "connection.json"));
            Equal(false, manager.Inspect(root, "Test").Valid);
        }
        finally { if (Directory.Exists(root)) Directory.Delete(root, true); }
    }),
    ("status parser accepts Windows PowerShell UTF-8 BOM output", () =>
    {
        var now = DateTimeOffset.UtcNow;
        var json = $$"""{"state":"Running","detail":"","currentPlayers":2,"maxPlayers":32,"uptimeSeconds":90,"serverFps":59,"updatedAtUtc":"{{now:O}}"}""";
        var preamble = System.Text.Encoding.UTF8.GetPreamble();
        var content = System.Text.Encoding.UTF8.GetBytes(json);
        var bytes = preamble.Concat(content).ToArray();
        var status = PalworldService.ParseStatus(bytes, now);
        Equal("Running", status.State);
        Equal(2, status.CurrentPlayers);
        Equal(59d, status.ServerFps);
    })
};

var failures = 0;
foreach (var test in tests)
{
    try { test.Run(); Console.WriteLine($"PASS {test.Name}"); }
    catch (Exception exception) { failures++; Console.Error.WriteLine($"FAIL {test.Name}: {exception.Message}"); }
}
Console.WriteLine($"{tests.Length - failures}/{tests.Length} passed");
return failures == 0 ? 0 : 1;

static SettingMetadata Metadata(string name, string type, string[]? options = null) =>
    new(name, "Test", name, "Test", type, default(JsonElement), null, null, options, "ini");

static void Equal<T>(T expected, T actual)
{
    if (!EqualityComparer<T>.Default.Equals(expected, actual))
        throw new InvalidOperationException($"Expected <{expected}> but received <{actual}>.");
}

static void Throws(Action action)
{
    try { action(); }
    catch (InvalidOperationException) { return; }
    throw new InvalidOperationException("Expected InvalidOperationException.");
}

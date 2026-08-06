using System.Diagnostics;
using System.Globalization;
using System.Text.Json;

namespace PalworldLiveMap.Reader;

internal static class Program
{
    private const int DefaultIntervalMilliseconds = 100;
    private const int DefaultEntityScanMilliseconds = 2000;
    private static readonly JsonSerializerOptions JsonOptions = new() { PropertyNamingPolicy = JsonNamingPolicy.CamelCase };

    private static async Task<int> Main(string[] args)
    {
        bool jsonLines = args.Contains("--json-lines", StringComparer.OrdinalIgnoreCase);
        try
        {
            if (args.Contains("--self-test", StringComparer.OrdinalIgnoreCase))
            {
                SelfTests.Run();
                return 0;
            }

            bool once = args.Contains("--once", StringComparer.OrdinalIgnoreCase);
            int? sampleLimit = once ? 1 : ReadSampleLimit(args);
            int interval = ReadInterval(args);
            int entityScanInterval = ReadEntityScanInterval(args);
            using var cancellation = new CancellationTokenSource();
            Console.CancelKeyPress += (_, eventArgs) =>
            {
                eventArgs.Cancel = true;
                cancellation.Cancel();
            };

            WriteStatus(jsonLines, "scanning", "Scanning Palworld's main module...");
            var attachTimer = Stopwatch.StartNew();
            using PalworldProbe probe = PalworldProbe.Attach();
            attachTimer.Stop();
            WriteStatus(
                jsonLines,
                "attached",
                $"Attached to PID {probe.ProcessId} in {attachTimer.Elapsed.TotalSeconds:F2}s.");
            if (!jsonLines)
            {
                Console.WriteLine(
                    $"FNames=0x{probe.NamePoolAddress:X}; GWorld*=0x{probe.WorldPointerAddress:X}");
            }

            string? inspectActorValue = ReadValue(args, "--inspect-actor=");
            if (!string.IsNullOrWhiteSpace(inspectActorValue))
            {
                if (!long.TryParse(inspectActorValue, NumberStyles.HexNumber, CultureInfo.InvariantCulture, out long actorAddress))
                {
                    throw new ArgumentException("--inspect-actor must be a hexadecimal actor address.");
                }
                ActorInspection actor = probe.InspectActor(actorAddress);
                WriteJson(new { schemaVersion = 1, type = "actor-inspection", capturedAtUtc = DateTimeOffset.UtcNow, actor });
                return 0;
            }

            if (args.Contains("--inspect-near-player", StringComparer.OrdinalIgnoreCase))
            {
                PlayerSnapshot player = probe.ReadPlayer();
                IReadOnlyList<ActorInspection> actors = probe.InspectWorldActors(centerX: player.X, centerY: player.Y);
                string outputPath = Path.GetFullPath(ReadValue(args, "--inspect-world-output=") ?? "nearby-live-inspection.jsonl");
                Directory.CreateDirectory(Path.GetDirectoryName(outputPath)!);
                using var writer = new StreamWriter(outputPath, false, new System.Text.UTF8Encoding(false));
                writer.WriteLine(JsonSerializer.Serialize(new { schemaVersion = 1, type = "world-inspection-header", capturedAtUtc = DateTimeOffset.UtcNow, player = new { x = player.X, y = player.Y, z = player.Z }, radius = 30_000 }, JsonOptions));
                foreach (ActorInspection actor in actors) writer.WriteLine(JsonSerializer.Serialize(new { schemaVersion = 1, type = "actor", actor }, JsonOptions));
                writer.WriteLine(JsonSerializer.Serialize(new { schemaVersion = 1, type = "world-inspection-summary", actorCount = actors.Count }, JsonOptions));
                WriteJson(new { schemaVersion = 1, type = "world-inspection-complete", outputPath, actorCount = actors.Count });
                return 0;
            }

            if (args.Contains("--inspect-world", StringComparer.OrdinalIgnoreCase))
            {
                var inspectionTimer = Stopwatch.StartNew();
                IReadOnlyList<ActorInspection> actors = probe.InspectWorldActors();
                inspectionTimer.Stop();
                string? outputPath = ReadValue(args, "--inspect-world-output=");
                if (string.IsNullOrWhiteSpace(outputPath))
                {
                    WriteJson(new { schemaVersion = 1, type = "world-inspection", capturedAtUtc = DateTimeOffset.UtcNow, elapsedMilliseconds = inspectionTimer.Elapsed.TotalMilliseconds, actors });
                }
                else
                {
                    outputPath = Path.GetFullPath(outputPath);
                    Directory.CreateDirectory(Path.GetDirectoryName(outputPath)!);
                    using var writer = new StreamWriter(outputPath, false, new System.Text.UTF8Encoding(false));
                    writer.WriteLine(JsonSerializer.Serialize(new { schemaVersion = 1, type = "world-inspection-header", capturedAtUtc = DateTimeOffset.UtcNow }, JsonOptions));
                    foreach (ActorInspection actor in actors)
                    {
                        writer.WriteLine(JsonSerializer.Serialize(new { schemaVersion = 1, type = "actor", actor }, JsonOptions));
                    }
                    writer.WriteLine(JsonSerializer.Serialize(new
                    {
                        schemaVersion = 1,
                        type = "world-inspection-summary",
                        elapsedMilliseconds = inspectionTimer.Elapsed.TotalMilliseconds,
                        actorCount = actors.Count,
                        classCount = actors.Select(actor => actor.ClassName).Distinct(StringComparer.Ordinal).Count(),
                    }, JsonOptions));
                    WriteJson(new { schemaVersion = 1, type = "world-inspection-complete", outputPath, actorCount = actors.Count, elapsedMilliseconds = inspectionTimer.Elapsed.TotalMilliseconds });
                }
                return 0;
            }

            long sequence = 0;
            int consecutiveWaiting = 0;
            var readTimes = new List<double>();
            DateTimeOffset nextEntityScan = DateTimeOffset.MinValue;
            while (!cancellation.IsCancellationRequested && !probe.HasExited)
            {
                var readTimer = Stopwatch.StartNew();
                try
                {
                    PlayerSnapshot snapshot = probe.ReadPlayer();
                    readTimer.Stop();
                    sequence++;
                    readTimes.Add(readTimer.Elapsed.TotalMilliseconds);
                    consecutiveWaiting = 0;
                    if (jsonLines)
                    {
                        WriteJson(new
                        {
                            schemaVersion = 1,
                            connected = true,
                            status = "live",
                            world = "Palworld",
                            sequence,
                            position = new { x = snapshot.X, y = snapshot.Y, z = snapshot.Z },
                            rotation = new { pitch = snapshot.Pitch, yaw = snapshot.Yaw, roll = snapshot.Roll },
                            readMilliseconds = readTimer.Elapsed.TotalMilliseconds,
                        });
                    }
                    else
                    {
                        Console.WriteLine(string.Create(
                            CultureInfo.InvariantCulture,
                            $"{sequence,6}  {readTimer.Elapsed.TotalMilliseconds,6:F2} ms  " +
                            $"X={snapshot.X,11:F2}  Y={snapshot.Y,11:F2}  Z={snapshot.Z,10:F2}  " +
                            $"Yaw={snapshot.Yaw,7:F2}  Pawn=0x{snapshot.PawnAddress:X}"));
                    }
                    if (sampleLimit.HasValue && sequence >= sampleLimit.Value)
                    {
                        break;
                    }
                }
                catch (InvalidOperationException exception) when (!once)
                {
                    consecutiveWaiting++;
                    if (consecutiveWaiting == 1 || consecutiveWaiting % 50 == 0)
                    {
                        WriteStatus(jsonLines, "waiting-for-player", exception.Message);
                    }
                }

                if (jsonLines && DateTimeOffset.UtcNow >= nextEntityScan)
                {
                    nextEntityScan = DateTimeOffset.UtcNow.AddMilliseconds(entityScanInterval);
                    var scanTimer = Stopwatch.StartNew();
                    try
                    {
                        IReadOnlyList<WorldEntitySnapshot> entities = probe.ReadEntities();
                        scanTimer.Stop();
                        WriteJson(new { schemaVersion = 1, type = "entities", capturedAtUtc = DateTimeOffset.UtcNow, scanMilliseconds = scanTimer.Elapsed.TotalMilliseconds, items = entities });
                        if (args.Contains("--inspect-ground-properties", StringComparer.OrdinalIgnoreCase))
                        {
                            WriteJson(new { schemaVersion = 1, type = "ground-properties", wrapper = probe.GroundResourcePropertyNames, visual = probe.GroundVisualPropertyNames });
                        }
                    }
                    catch (Exception exception) when (exception is InvalidOperationException or InvalidDataException or MissingMemberException)
                    {
                        WriteJson(new { schemaVersion = 1, type = "entities-error", message = exception.Message });
                    }
                }

                await Task.Delay(interval, cancellation.Token).ConfigureAwait(false);
            }

            if (jsonLines)
            {
                WriteStatus(false, probe.HasExited ? "palworld-exited" : "reader-stopped", string.Empty, forceJson: true);
            }
            else
            {
                PrintSummary(readTimes);
                Console.WriteLine(probe.HasExited ? "Palworld exited; detached." : "Reader stopped.");
            }
            return 0;
        }
        catch (OperationCanceledException)
        {
            WriteStatus(jsonLines, "reader-stopped", "Reader stopped.");
            return 0;
        }
        catch (Exception exception)
        {
            if (jsonLines)
            {
                WriteJson(new { schemaVersion = 1, connected = false, status = "reader-error", message = exception.Message });
            }
            else
            {
                Console.Error.WriteLine($"Reader failed: {exception.Message}");
            }
            return 1;
        }
    }

    private static void WriteStatus(bool jsonLines, string status, string message, bool forceJson = false)
    {
        if (jsonLines || forceJson)
        {
            WriteJson(new { schemaVersion = 1, connected = false, status, message });
        }
        else if (!string.IsNullOrWhiteSpace(message))
        {
            Console.WriteLine(message);
        }
    }

    private static void WriteJson<T>(T value)
    {
        Console.WriteLine(JsonSerializer.Serialize(value, JsonOptions));
        Console.Out.Flush();
    }

    private static string? ReadValue(string[] args, string prefix) =>
        args.FirstOrDefault(argument => argument.StartsWith(prefix, StringComparison.OrdinalIgnoreCase))?[prefix.Length..];

    private static int ReadInterval(string[] args)
    {
        string? value = args.FirstOrDefault(
            argument => argument.StartsWith("--interval-ms=", StringComparison.OrdinalIgnoreCase));
        if (value is null) return DefaultIntervalMilliseconds;
        string number = value[(value.IndexOf('=') + 1)..];
        if (!int.TryParse(number, NumberStyles.None, CultureInfo.InvariantCulture, out int interval)
            || interval is < 25 or > 5000)
        {
            throw new ArgumentException("--interval-ms must be between 25 and 5000.");
        }
        return interval;
    }

    private static int? ReadSampleLimit(string[] args)
    {
        string? value = args.FirstOrDefault(
            argument => argument.StartsWith("--samples=", StringComparison.OrdinalIgnoreCase));
        if (value is null) return null;
        string number = value[(value.IndexOf('=') + 1)..];
        if (!int.TryParse(number, NumberStyles.None, CultureInfo.InvariantCulture, out int samples)
            || samples is < 1 or > 10_000)
        {
            throw new ArgumentException("--samples must be between 1 and 10000.");
        }
        return samples;
    }

    private static int ReadEntityScanInterval(string[] args)
    {
        string? value = args.FirstOrDefault(argument => argument.StartsWith("--entity-scan-ms=", StringComparison.OrdinalIgnoreCase));
        if (value is null) return DefaultEntityScanMilliseconds;
        string number = value[(value.IndexOf('=') + 1)..];
        if (!int.TryParse(number, NumberStyles.None, CultureInfo.InvariantCulture, out int interval) || interval is < 500 or > 30_000)
        {
            throw new ArgumentException("--entity-scan-ms must be between 500 and 30000.");
        }
        return interval;
    }

    private static void PrintSummary(List<double> readTimes)
    {
        if (readTimes.Count == 0) return;
        double[] ordered = readTimes.Order().ToArray();
        int p95Index = Math.Clamp((int)Math.Ceiling(ordered.Length * 0.95) - 1, 0, ordered.Length - 1);
        Console.WriteLine(string.Create(
            CultureInfo.InvariantCulture,
            $"Read summary: n={ordered.Length}, avg={ordered.Average():F3} ms, " +
            $"p95={ordered[p95Index]:F3} ms, max={ordered[^1]:F3} ms."));
    }
}

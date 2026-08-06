using System.Diagnostics;
using PalworldLiveMap.Reader.Memory;
using PalworldLiveMap.Reader.Unreal;

namespace PalworldLiveMap.Reader;

internal sealed class PalworldProbe : IDisposable
{
    private const int MaximumLevels = 4096;
    private const int MaximumActorsPerLevel = 100_000;
    private static readonly string[] ProcessNames =
    [
        "Palworld-Win64-Shipping",
        "Palworld-WinGDK-Shipping",
        "Palworld-Wingdk-Shipping",
    ];

    private readonly ProcessMemory _memory;
    private readonly UnrealGlobals _globals;
    private readonly UnrealReflection _reflection;
    private readonly Dictionary<long, (string ClassName, string ObjectName, string? Layer, string? CharacterId, bool IsTamed)> _actorCache = new();
    private int? _levelActorsOffset;
    private long _localPawnAddress;
    private IReadOnlyList<string> _groundResourcePropertyNames = [];
    private IReadOnlyList<string> _groundVisualPropertyNames = [];

    private PalworldProbe(
        ProcessMemory memory,
        UnrealGlobals globals,
        UnrealReflection reflection)
    {
        _memory = memory;
        _globals = globals;
        _reflection = reflection;
    }

    internal int ProcessId => _memory.Process.Id;
    internal long ModuleBase => _memory.ModuleBase;
    internal int ModuleSize => _memory.ModuleSize;
    internal long NamePoolAddress => _globals.NamePool;
    internal long WorldPointerAddress => _globals.WorldPointerAddress;
    internal bool HasExited => _memory.Process.HasExited;
    internal IReadOnlyList<string> GroundResourcePropertyNames => _groundResourcePropertyNames;
    internal IReadOnlyList<string> GroundVisualPropertyNames => _groundVisualPropertyNames;

    internal static PalworldProbe Attach()
    {
        Process? process = null;
        foreach (string name in ProcessNames)
        {
            process = Process.GetProcessesByName(name)
                .OrderBy(candidate => candidate.StartTime)
                .FirstOrDefault();
            if (process is not null)
            {
                break;
            }
        }
        if (process is null)
        {
            throw new InvalidOperationException("No supported Palworld gameplay process is running.");
        }

        ProcessMemory memory = ProcessMemory.Attach(process);
        try
        {
            byte[] module = memory.ReadModuleImage();
            UnrealGlobals globals = UnrealGlobals.Discover(memory, module);
            var names = new FNamePool(memory, globals.NamePool);
            names.Validate();
            var reflection = new UnrealReflection(memory, names);
            return new PalworldProbe(memory, globals, reflection);
        }
        catch
        {
            memory.Dispose();
            throw;
        }
    }

    internal PlayerSnapshot ReadPlayer()
    {
        long world = _memory.ReadPointer(_globals.WorldPointerAddress);
        if (world == 0)
        {
            throw new InvalidOperationException("Palworld has not created a world yet.");
        }

        long gameInstance = RequiredObject(
            _reflection.ReadObject(world, "OwningGameInstance"),
            "OwningGameInstance");
        (long localPlayers, int playerCount) = _reflection.ReadArray(gameInstance, "LocalPlayers");
        if (playerCount < 1)
        {
            throw new InvalidOperationException("The current world has no local player.");
        }

        long localPlayer = RequiredObject(_memory.ReadPointer(localPlayers), "LocalPlayers[0]");
        long controller = RequiredObject(
            _reflection.ReadObject(localPlayer, "PlayerController"),
            "PlayerController");
        long pawn = RequiredObject(
            _reflection.ReadObject(controller, "AcknowledgedPawn"),
            "AcknowledgedPawn");
        _localPawnAddress = pawn;
        long root = RequiredObject(
            _reflection.ReadObject(pawn, "RootComponent"),
            "RootComponent");

        long location = _reflection.GetStructAddress(root, "RelativeLocation");
        long rotation = _reflection.GetStructAddress(root, "RelativeRotation");
        double x = _memory.ReadDouble(location);
        double y = _memory.ReadDouble(location + 8);
        double z = _memory.ReadDouble(location + 16);
        double pitch = _memory.ReadDouble(rotation);
        double yaw = _memory.ReadDouble(rotation + 8);
        double roll = _memory.ReadDouble(rotation + 16);
        ValidateFinite(x, nameof(x));
        ValidateFinite(y, nameof(y));
        ValidateFinite(z, nameof(z));
        ValidateFinite(pitch, nameof(pitch));
        ValidateFinite(yaw, nameof(yaw));
        ValidateFinite(roll, nameof(roll));

        return new PlayerSnapshot(
            DateTimeOffset.UtcNow,
            pawn,
            x,
            y,
            z,
            pitch,
            yaw,
            roll);
    }

    internal IReadOnlyList<WorldEntitySnapshot> ReadEntities()
    {
        long world = RequiredObject(_memory.ReadPointer(_globals.WorldPointerAddress), "GWorld");
        (long levels, int levelCount) = _reflection.ReadArray(world, "Levels");
        if (levelCount > MaximumLevels)
        {
            throw new InvalidDataException($"World reported an excessive level count: {levelCount}.");
        }

        var entities = new List<WorldEntitySnapshot>();
        var visited = new HashSet<long>();
        for (int levelIndex = 0; levelIndex < levelCount; levelIndex++)
        {
            long level = _memory.ReadPointer(levels + (levelIndex * 8L));
            if (!ProcessMemory.IsCanonicalPointer(level)) continue;
            (long actors, int actorCount) = ReadLevelActors(level);
            if (actorCount > MaximumActorsPerLevel)
            {
                throw new InvalidDataException($"Level {levelIndex} reported an excessive actor count: {actorCount}.");
            }
            for (int actorIndex = 0; actorIndex < actorCount; actorIndex++)
            {
                long actor = _memory.ReadPointer(actors + (actorIndex * 8L));
                if (!ProcessMemory.IsCanonicalPointer(actor) || actor == _localPawnAddress || !visited.Add(actor)) continue;
                try
                {
                    (string className, string objectName, string? layer, string? characterId, bool isTamed) = GetActorIdentity(actor);
                    if (layer == "ground-resources" && _groundResourcePropertyNames.Count == 0)
                    {
                        _groundResourcePropertyNames = _reflection.GetPropertyNames(actor);
                    }
                    if (layer is null) continue;
                    long root = _reflection.ReadObject(actor, "RootComponent");
                    if (!ProcessMemory.IsCanonicalPointer(root)) continue;
                    (double x, double y, double z) = ReadWorldLocation(root);
                    if (!double.IsFinite(x) || !double.IsFinite(y) || !double.IsFinite(z)) continue;
                    if (ActorLayerClassifier.IsUnreliableWorldOrigin(className, x, y)) continue;
                    entities.Add(new WorldEntitySnapshot($"{actor:X}", layer, objectName, className, characterId, isTamed, x, y, z));
                }
                catch (Exception exception) when (exception is InvalidDataException or MissingMemberException)
                {
                    // Actor arrays can change while they are read. Skip only the unstable actor.
                }
            }
        }
        return CollapseNearbyStructureMarkers(entities, "oil-rigs", 150_000);
    }

    private (double X, double Y, double Z) ReadWorldLocation(long sceneComponent)
    {
        try
        {
            // UE5's FTransform stores its world-space translation after the
            // four-double rotation quaternion. Unlike RelativeLocation, this
            // remains a usable map coordinate for pickups attached to a spawner.
            long transform = _reflection.GetStructAddress(sceneComponent, "ComponentToWorld");
            double x = _memory.ReadDouble(transform + 32);
            double y = _memory.ReadDouble(transform + 40);
            double z = _memory.ReadDouble(transform + 48);
            if (double.IsFinite(x) && double.IsFinite(y) && double.IsFinite(z)) return (x, y, z);
        }
        catch (Exception exception) when (exception is InvalidDataException or MissingMemberException)
        {
            // Some component subclasses do not expose ComponentToWorld through
            // reflection. Their relative location is valid when they are roots.
        }

        long location = _reflection.GetStructAddress(sceneComponent, "RelativeLocation");
        return (
            _memory.ReadDouble(location),
            _memory.ReadDouble(location + 8),
            _memory.ReadDouble(location + 16));
    }

    internal IReadOnlyList<ActorInspection> InspectWorldActors(int nestedDepth = 2, int maximumNestedObjects = 96, double? centerX = null, double? centerY = null, double radius = 30_000)
    {
        long world = RequiredObject(_memory.ReadPointer(_globals.WorldPointerAddress), "GWorld");
        (long levels, int levelCount) = _reflection.ReadArray(world, "Levels");
        if (levelCount > MaximumLevels) throw new InvalidDataException($"World reported an excessive level count: {levelCount}.");

        var results = new List<ActorInspection>();
        var visitedActors = new HashSet<long>();
        for (int levelIndex = 0; levelIndex < levelCount; levelIndex++)
        {
            long level = _memory.ReadPointer(levels + (levelIndex * 8L));
            if (!ProcessMemory.IsCanonicalPointer(level)) continue;
            (long actors, int actorCount) = ReadLevelActors(level);
            for (int actorIndex = 0; actorIndex < actorCount; actorIndex++)
            {
                long actor = _memory.ReadPointer(actors + (actorIndex * 8L));
                if (!ProcessMemory.IsCanonicalPointer(actor) || !visitedActors.Add(actor)) continue;
                try
                {
                    string className = _reflection.GetClassName(actor);
                    string objectName = _reflection.GetObjectName(actor);
                    (double? x, double? y, double? z) = TryReadLocation(actor);
                    if (centerX.HasValue && centerY.HasValue && (!x.HasValue || !y.HasValue || Math.Sqrt(Math.Pow(x.Value - centerX.Value, 2) + Math.Pow(y.Value - centerY.Value, 2)) > radius)) continue;
                    IReadOnlyList<string> properties = _reflection.GetPropertyNames(actor);
                    var nested = new List<NestedObjectInspection>();
                    InspectNestedObjects(actor, string.Empty, nestedDepth, maximumNestedObjects, new HashSet<long> { actor }, nested);
                    results.Add(new ActorInspection($"{actor:X}", className, objectName, x, y, z, properties, nested, InspectOwnershipSignals(actor, className, nested)));
                }
                catch (Exception exception) when (exception is InvalidDataException or MissingMemberException or System.ComponentModel.Win32Exception)
                {
                    // The world may mutate during inspection. Skip only the unstable actor.
                }
            }
        }
        return results;
    }

    internal ActorInspection InspectActor(long actor, int nestedDepth = 3, int maximumNestedObjects = 192)
    {
        if (!ProcessMemory.IsCanonicalPointer(actor)) throw new InvalidDataException("Actor address is not a canonical process pointer.");
        string className = _reflection.GetClassName(actor);
        string objectName = _reflection.GetObjectName(actor);
        (double? x, double? y, double? z) = TryReadLocation(actor);
        IReadOnlyList<string> properties = _reflection.GetPropertyNames(actor);
        var nested = new List<NestedObjectInspection>();
        InspectNestedObjects(actor, string.Empty, nestedDepth, maximumNestedObjects, new HashSet<long> { actor }, nested);
        return new ActorInspection($"{actor:X}", className, objectName, x, y, z, properties, nested, InspectOwnershipSignals(actor, className, nested));
    }

    private IReadOnlyList<PropertySignalInspection> InspectOwnershipSignals(long rootAddress, string rootClassName, IReadOnlyList<NestedObjectInspection> nested)
    {
        var targets = new List<(long Address, string Path, string ClassName)> { (rootAddress, string.Empty, rootClassName) };
        foreach (NestedObjectInspection item in nested.Where(item => item.ClassName is "PalIndividualCharacterParameter" or "PalIndividualCharacterHandle"))
        {
            if (long.TryParse(item.Address, System.Globalization.NumberStyles.HexNumber, System.Globalization.CultureInfo.InvariantCulture, out long address))
                targets.Add((address, item.Path, item.ClassName));
        }
        var results = new List<PropertySignalInspection>();
        foreach ((long address, string path, string className) in targets)
        {
            string[] names = className switch
            {
                "PalIndividualCharacterParameter" => ["IndividualId", "BaseCampId", "bIsUncapturable", "bIsForceCapturable", "bIsParts", "bIsInRaidArea"],
                "PalIndividualCharacterHandle" => ["ID"],
                _ => ["bInBaseReplication", "Owner"]
            };
            foreach (string name in names)
            {
                try
                {
                    int length = name.StartsWith("b", StringComparison.Ordinal) ? 1 : 16;
                    byte[] bytes = _reflection.ReadPropertyBytes(address, name, length);
                    results.Add(new PropertySignalInspection(
                        string.IsNullOrEmpty(path) ? name : $"{path}.{name}",
                        Convert.ToHexString(bytes),
                        bytes.All(value => value == 0),
                        bytes[0]));
                }
                catch (Exception exception) when (exception is InvalidDataException or MissingMemberException or System.ComponentModel.Win32Exception) { }
            }
        }
        return results;
    }

    private (double? X, double? Y, double? Z) TryReadLocation(long actor)
    {
        try
        {
            long root = _reflection.ReadObject(actor, "RootComponent");
            if (!ProcessMemory.IsCanonicalPointer(root)) return (null, null, null);
            (double x, double y, double z) = ReadWorldLocation(root);
            return double.IsFinite(x) && double.IsFinite(y) && double.IsFinite(z) ? (x, y, z) : (null, null, null);
        }
        catch (Exception exception) when (exception is InvalidDataException or MissingMemberException or System.ComponentModel.Win32Exception)
        {
            return (null, null, null);
        }
    }

    private void InspectNestedObjects(
        long objectAddress,
        string path,
        int depth,
        int maximumObjects,
        HashSet<long> visited,
        List<NestedObjectInspection> results)
    {
        if (depth <= 0 || results.Count >= maximumObjects) return;
        foreach (string property in _reflection.GetPropertyNames(objectAddress).Take(256))
        {
            if (results.Count >= maximumObjects) return;
            try
            {
                long nestedAddress = _reflection.ReadObject(objectAddress, property);
                if (!ProcessMemory.IsCanonicalPointer(nestedAddress) || !visited.Add(nestedAddress)) continue;
                string className = _reflection.GetClassName(nestedAddress);
                string objectName = _reflection.GetObjectName(nestedAddress);
                string nestedPath = string.IsNullOrEmpty(path) ? property : $"{path}.{property}";
                results.Add(new NestedObjectInspection(nestedPath, className, objectName, $"{nestedAddress:X}"));
                InspectNestedObjects(nestedAddress, nestedPath, depth - 1, maximumObjects, visited, results);
            }
            catch (Exception exception) when (exception is InvalidDataException or MissingMemberException or System.ComponentModel.Win32Exception)
            {
                // Non-object properties are expected; only validated UObject references are retained.
            }
        }
    }

    private static IReadOnlyList<WorldEntitySnapshot> CollapseNearbyStructureMarkers(
        IReadOnlyList<WorldEntitySnapshot> entities,
        string layer,
        double radius)
    {
        var result = entities.Where(entity => entity.Layer != layer).ToList();
        var remaining = new HashSet<WorldEntitySnapshot>(entities.Where(entity => entity.Layer == layer));
        double radiusSquared = radius * radius;
        while (remaining.Count > 0)
        {
            WorldEntitySnapshot seed = remaining.First();
            remaining.Remove(seed);
            var cluster = new List<WorldEntitySnapshot> { seed };
            var queue = new Queue<WorldEntitySnapshot>();
            queue.Enqueue(seed);
            while (queue.Count > 0)
            {
                WorldEntitySnapshot current = queue.Dequeue();
                WorldEntitySnapshot[] neighbors = remaining.Where(candidate =>
                {
                    double dx = candidate.X - current.X;
                    double dy = candidate.Y - current.Y;
                    return (dx * dx) + (dy * dy) <= radiusSquared;
                }).ToArray();
                foreach (WorldEntitySnapshot neighbor in neighbors)
                {
                    remaining.Remove(neighbor);
                    cluster.Add(neighbor);
                    queue.Enqueue(neighbor);
                }
            }
            result.Add(seed with
            {
                Id = $"oil-rig-{seed.Id}",
                Name = "Oil Rig",
                X = cluster.Average(entity => entity.X),
                Y = cluster.Average(entity => entity.Y),
                Z = cluster.Average(entity => entity.Z),
            });
        }
        return result;
    }

    private (long Data, int Count) ReadLevelActors(long level)
    {
        if (_levelActorsOffset.HasValue)
        {
            return ReadArrayAt(level, _levelActorsOffset.Value);
        }
        try
        {
            return _reflection.ReadArray(level, "Actors");
        }
        catch (MissingMemberException)
        {
            // ULevel::Actors is native in current Palworld builds and may not be an FProperty.
        }

        int bestOffset = -1;
        int bestScore = 0;
        for (int offset = 0x40; offset <= 0x300; offset += 8)
        {
            try
            {
                (long data, int count) = ReadArrayAt(level, offset);
                if (count < 2 || count > MaximumActorsPerLevel) continue;
                int score = 0;
                int samples = Math.Min(count, 24);
                for (int index = 0; index < samples; index++)
                {
                    long candidate = _memory.ReadPointer(data + (index * 8L));
                    if (!IsPlausibleHeapPointer(candidate)) continue;
                    try
                    {
                        string className = _reflection.GetClassName(candidate);
                        if (!string.IsNullOrWhiteSpace(className)) score++;
                    }
                    catch (Exception exception) when (exception is InvalidDataException or System.ComponentModel.Win32Exception) { }
                }
                if (score > bestScore)
                {
                    bestOffset = offset;
                    bestScore = score;
                }
            }
            catch (Exception exception) when (exception is InvalidDataException or System.ComponentModel.Win32Exception) { }
        }
        if (bestOffset < 0 || bestScore < 2)
        {
            throw new MissingMemberException("Could not discover the validated ULevel actor array layout.");
        }
        _levelActorsOffset = bestOffset;
        return ReadArrayAt(level, bestOffset);
    }

    private (long Data, int Count) ReadArrayAt(long objectAddress, int offset)
    {
        long data = _memory.ReadPointer(objectAddress + offset);
        int count = _memory.ReadInt32(objectAddress + offset + 8);
        int capacity = _memory.ReadInt32(objectAddress + offset + 12);
        if (count < 0 || capacity < count || capacity > 1_000_000 || (count > 0 && !IsPlausibleHeapPointer(data)))
        {
            throw new InvalidDataException($"Invalid array candidate at ULevel+0x{offset:X}.");
        }
        return (data, count);
    }

    private static bool IsPlausibleHeapPointer(long value) =>
        value >= 0x1_0000_0000 && ProcessMemory.IsCanonicalPointer(value) && (value & 7) == 0;

    private (string ClassName, string ObjectName, string? Layer, string? CharacterId, bool IsTamed) GetActorIdentity(long actor)
    {
        if (_actorCache.TryGetValue(actor, out var cached)) return cached;
        string className = _reflection.GetClassName(actor);
        string objectName = _reflection.GetObjectName(actor);
        if (className.Contains("TreasureBox_VisibleContent", StringComparison.OrdinalIgnoreCase))
        {
            try
            {
                long visualActor = _reflection.ReadObject(actor, "VisualActor");
                if (ProcessMemory.IsCanonicalPointer(visualActor))
                {
                    long concreteActor = visualActor;
                    if (_reflection.GetClassName(visualActor).Contains("ChildActorComponent", StringComparison.OrdinalIgnoreCase))
                    {
                        long childActor = _reflection.ReadObject(visualActor, "ChildActor");
                        if (ProcessMemory.IsCanonicalPointer(childActor)) concreteActor = childActor;
                    }
                    className += " " + _reflection.GetClassName(concreteActor);
                    objectName += " " + _reflection.GetObjectName(concreteActor);
                    if (_groundVisualPropertyNames.Count == 0) _groundVisualPropertyNames = _reflection.GetPropertyNames(concreteActor);
                    try
                    {
                        long meshComponent = _reflection.ReadObject(concreteActor, "StaticMesh");
                        long meshAsset = _reflection.ReadObject(meshComponent, "StaticMesh");
                        if (ProcessMemory.IsCanonicalPointer(meshAsset)) objectName += " " + _reflection.GetObjectName(meshAsset);
                    }
                    catch (Exception exception) when (exception is InvalidDataException or MissingMemberException or System.ComponentModel.Win32Exception) { }
                }
            }
            catch (Exception exception) when (exception is InvalidDataException or MissingMemberException or System.ComponentModel.Win32Exception) { }
        }
        string? characterId = null;
        bool isPalActor = className.Contains("PalCharacter", StringComparison.OrdinalIgnoreCase)
            || className.Contains("PalMonster", StringComparison.OrdinalIgnoreCase)
            || className.Contains("_BOSS_C", StringComparison.OrdinalIgnoreCase);
        if (isPalActor)
        {
            foreach (string property in new[] { "CharacterID", "CharacterId", "CharacterIDName" })
            {
                try
                {
                    characterId = _reflection.ReadName(actor, property);
                    break;
                }
                catch (MissingMemberException) { }
            }
        }
        bool isTamed = isPalActor && IsPlayerOwnedPal(actor);
        var result = (className, objectName, ActorLayerClassifier.Classify(className, objectName, characterId), characterId, isTamed);
        if (_actorCache.Count < 250_000) _actorCache[actor] = result;
        return result;
    }

    private bool IsPlayerOwnedPal(long actor)
    {
        // Party/active Pals expose a Trainer relationship. Base workers are
        // instead linked through PalIndividualCharacterParameter.BaseCampId.
        try
        {
            long parameters = _reflection.ReadObject(actor, "CharacterParameterComponent");
            if (ProcessMemory.IsCanonicalPointer(parameters))
            {
                long trainer = _reflection.ReadObject(parameters, "Trainer");
                if (ProcessMemory.IsCanonicalPointer(trainer)
                    && _reflection.GetClassName(trainer).Contains("Player", StringComparison.OrdinalIgnoreCase)) return true;
            }
        }
        catch (Exception exception) when (exception is InvalidDataException or MissingMemberException or System.ComponentModel.Win32Exception)
        {
            // Not every Pal state exposes Trainer; continue with base ownership.
        }
        try
        {
            long cry = _reflection.ReadObject(actor, "BP_PalCryComponent");
            if (!ProcessMemory.IsCanonicalPointer(cry)) return false;
            long individual = _reflection.ReadObject(cry, "IndividualParameter");
            if (!ProcessMemory.IsCanonicalPointer(individual)) return false;
            byte[] baseCampId = _reflection.ReadPropertyBytes(individual, "BaseCampId", 16);
            return baseCampId.Any(value => value != 0);
        }
        catch (Exception exception) when (exception is InvalidDataException or MissingMemberException or System.ComponentModel.Win32Exception)
        {
            return false;
        }
    }

    public void Dispose() => _memory.Dispose();

    private static long RequiredObject(long value, string name)
    {
        if (!ProcessMemory.IsCanonicalPointer(value))
        {
            throw new InvalidOperationException($"{name} is unavailable.");
        }
        return value;
    }

    private static void ValidateFinite(double value, string name)
    {
        if (!double.IsFinite(value))
        {
            throw new InvalidDataException($"Player {name} is not finite.");
        }
    }
}

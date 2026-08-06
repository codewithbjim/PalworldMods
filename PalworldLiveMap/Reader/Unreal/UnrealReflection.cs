using PalworldLiveMap.Reader.Memory;

namespace PalworldLiveMap.Reader.Unreal;

internal sealed class UnrealReflection
{
    private const int ObjectClassOffset = 0x10;
    private const int ObjectNameOffset = 0x18;
    private const int StructSuperOffset = 0x40;
    private const int StructChildPropertiesOffset = 0x50;
    private const int FieldNextOffset = 0x20;
    private const int FieldNameOffset = 0x28;
    private const int PropertyValueOffsetOffset = 0x4C;
    private const int MaximumClassDepth = 64;
    private const int MaximumFieldsPerClass = 4096;

    private readonly ProcessMemory _memory;
    private readonly FNamePool _names;
    private readonly Dictionary<(long Class, string Name), int> _offsetCache = new();

    internal UnrealReflection(ProcessMemory memory, FNamePool names)
    {
        _memory = memory;
        _names = names;
    }

    internal string GetObjectName(long objectAddress)
    {
        EnsureObject(objectAddress, nameof(objectAddress));
        int nameIndex = _memory.ReadInt32(objectAddress + ObjectNameOffset);
        return _names.GetName(nameIndex);
    }

    internal string GetClassName(long objectAddress)
    {
        long classAddress = GetClass(objectAddress);
        return GetObjectName(classAddress);
    }

    internal long ReadObject(long objectAddress, string propertyName)
    {
        int offset = GetPropertyOffset(objectAddress, propertyName);
        return _memory.ReadPointer(objectAddress + offset);
    }

    internal (long Data, int Count) ReadArray(long objectAddress, string propertyName)
    {
        int offset = GetPropertyOffset(objectAddress, propertyName);
        long data = _memory.ReadPointer(objectAddress + offset);
        int count = _memory.ReadInt32(objectAddress + offset + 8);
        int capacity = _memory.ReadInt32(objectAddress + offset + 12);
        if (count < 0 || capacity < count || capacity > 1_000_000)
        {
            throw new InvalidDataException(
                $"Property '{propertyName}' returned invalid TArray bounds {count}/{capacity}.");
        }
        if (count > 0 && data == 0)
        {
            throw new InvalidDataException($"Property '{propertyName}' has items but a null data pointer.");
        }
        return (data, count);
    }

    internal long GetStructAddress(long objectAddress, string propertyName)
    {
        int offset = GetPropertyOffset(objectAddress, propertyName);
        return checked(objectAddress + offset);
    }

    internal string ReadName(long objectAddress, string propertyName)
    {
        int offset = GetPropertyOffset(objectAddress, propertyName);
        int comparisonIndex = _memory.ReadInt32(objectAddress + offset);
        return _names.GetName(comparisonIndex);
    }

    internal int GetPropertyOffset(long objectAddress, string propertyName)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(propertyName);
        long originalClass = GetClass(objectAddress);
        if (_offsetCache.TryGetValue((originalClass, propertyName), out int cached))
        {
            return cached;
        }

        long classAddress = originalClass;
        for (int depth = 0; depth < MaximumClassDepth && classAddress != 0; depth++)
        {
            long fieldAddress = _memory.ReadPointer(classAddress + StructChildPropertiesOffset);
            var visited = new HashSet<long>();
            for (int fieldCount = 0;
                 fieldCount < MaximumFieldsPerClass && fieldAddress != 0;
                 fieldCount++)
            {
                if (!visited.Add(fieldAddress))
                {
                    throw new InvalidDataException(
                        $"The property list for class 0x{classAddress:X} contains a cycle.");
                }
                int fieldNameIndex = _memory.ReadInt32(fieldAddress + FieldNameOffset);
                string fieldName = _names.GetName(fieldNameIndex);
                if (string.Equals(fieldName, propertyName, StringComparison.Ordinal))
                {
                    int offset = _memory.ReadInt32(fieldAddress + PropertyValueOffsetOffset);
                    if (offset < 0 || offset > 0x100000)
                    {
                        throw new InvalidDataException(
                            $"Property '{propertyName}' reported invalid offset 0x{offset:X}.");
                    }
                    _offsetCache[(originalClass, propertyName)] = offset;
                    return offset;
                }
                fieldAddress = _memory.ReadPointer(fieldAddress + FieldNextOffset);
            }
            classAddress = _memory.ReadPointer(classAddress + StructSuperOffset);
        }

        string className;
        try
        {
            className = GetObjectName(originalClass);
        }
        catch
        {
            className = $"0x{originalClass:X}";
        }
        throw new MissingMemberException(
            $"Property '{propertyName}' was not found on class '{className}'.");
    }

    internal byte[] ReadPropertyBytes(long objectAddress, string propertyName, int length)
    {
        if (length is < 1 or > 64) throw new ArgumentOutOfRangeException(nameof(length));
        int offset = GetPropertyOffset(objectAddress, propertyName);
        return _memory.ReadBytes(objectAddress + offset, length);
    }

    internal IReadOnlyList<string> GetPropertyNames(long objectAddress)
    {
        long classAddress = GetClass(objectAddress);
        var names = new List<string>();
        var seenNames = new HashSet<string>(StringComparer.Ordinal);
        for (int depth = 0; depth < MaximumClassDepth && classAddress != 0; depth++)
        {
            long fieldAddress = _memory.ReadPointer(classAddress + StructChildPropertiesOffset);
            var visited = new HashSet<long>();
            for (int fieldCount = 0; fieldCount < MaximumFieldsPerClass && fieldAddress != 0; fieldCount++)
            {
                if (!visited.Add(fieldAddress)) break;
                string fieldName = _names.GetName(_memory.ReadInt32(fieldAddress + FieldNameOffset));
                if (seenNames.Add(fieldName)) names.Add(fieldName);
                fieldAddress = _memory.ReadPointer(fieldAddress + FieldNextOffset);
            }
            classAddress = _memory.ReadPointer(classAddress + StructSuperOffset);
        }
        return names;
    }

    private long GetClass(long objectAddress)
    {
        EnsureObject(objectAddress, nameof(objectAddress));
        long classAddress = _memory.ReadPointer(objectAddress + ObjectClassOffset);
        EnsureObject(classAddress, "classAddress");
        return classAddress;
    }

    private static void EnsureObject(long address, string label)
    {
        if (!ProcessMemory.IsCanonicalPointer(address))
        {
            throw new InvalidDataException($"{label} is not a canonical object address: 0x{address:X}.");
        }
    }
}

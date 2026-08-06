using System.Text;
using PalworldLiveMap.Reader.Memory;

namespace PalworldLiveMap.Reader.Unreal;

internal sealed class FNamePool
{
    private const int BlocksOffset = 0x10;
    private const int MaximumNameLength = 1024;
    private readonly ProcessMemory _memory;
    private readonly long _address;
    private readonly Dictionary<int, string> _cache = new();

    internal FNamePool(ProcessMemory memory, long address)
    {
        _memory = memory;
        _address = address;
    }

    internal string GetName(int comparisonIndex)
    {
        if (comparisonIndex < 0)
        {
            throw new InvalidDataException($"Rejected negative FName index {comparisonIndex}.");
        }
        if (_cache.TryGetValue(comparisonIndex, out string? cached))
        {
            return cached;
        }

        int block = comparisonIndex >> 16;
        int offset = comparisonIndex & 0xFFFF;
        long blockAddress = _memory.ReadPointer(_address + BlocksOffset + (block * 8L));
        if (blockAddress == 0)
        {
            throw new InvalidDataException($"FName block {block} is null.");
        }
        long entryAddress = checked(blockAddress + (offset * 2L));
        ushort header = _memory.ReadUInt16(entryAddress);
        int length = header >> 6;
        bool wide = (header & 1) != 0;
        if (length <= 0 || length > MaximumNameLength)
        {
            throw new InvalidDataException(
                $"FName {comparisonIndex} reported invalid length {length}.");
        }

        byte[] bytes = _memory.ReadBytes(entryAddress + 2, checked(length * (wide ? 2 : 1)));
        string name = wide
            ? Encoding.Unicode.GetString(bytes)
            : Encoding.UTF8.GetString(bytes);
        _cache[comparisonIndex] = name;
        return name;
    }

    internal void Validate()
    {
        string sentinel = GetName(3);
        if (!string.Equals(sentinel, "ByteProperty", StringComparison.Ordinal))
        {
            throw new InvalidDataException(
                $"The FName pool failed validation: index 3 was '{sentinel}'.");
        }
    }
}

using System.Buffers.Binary;
using System.Text;
using PalworldLiveMap.Reader.Memory;

namespace PalworldLiveMap.Reader.Unreal;

internal sealed record UnrealGlobals(long NamePool, long WorldPointerAddress)
{
    private const string NamePoolSignature = "74 09 48 8D 15 ? ? ? ? EB 16";
    private const string WorldAnchor = "    SeamlessTravel FlushLevelStreaming";

    internal static UnrealGlobals Discover(ProcessMemory memory, ReadOnlySpan<byte> module)
    {
        BytePattern namePattern = BytePattern.Parse(NamePoolSignature);
        int nameInstruction = namePattern.Find(module);
        if (nameInstruction < 0)
        {
            throw new InvalidDataException("The Unreal FName signature was not found.");
        }

        int nameDisplacement = BinaryPrimitives.ReadInt32LittleEndian(
            module.Slice(nameInstruction + 5, sizeof(int)));
        long namePool = checked(memory.ModuleBase + nameInstruction + 9L + nameDisplacement);
        if (!ProcessMemory.IsCanonicalPointer(namePool))
        {
            throw new InvalidDataException("The FName signature resolved outside user memory.");
        }

        byte[] anchorBytes = Encoding.Unicode.GetBytes(WorldAnchor);
        int anchorOffset = module.IndexOf(anchorBytes);
        if (anchorOffset < 0)
        {
            throw new InvalidDataException("The Unreal world anchor string was not found.");
        }
        long anchorAddress = memory.ModuleBase + anchorOffset;
        int referenceOffset = FindRipRelativeReference(module, memory.ModuleBase, anchorAddress);
        if (referenceOffset < 0)
        {
            throw new InvalidDataException("No RIP-relative reference to the Unreal world anchor was found.");
        }

        BytePattern worldStore = BytePattern.Parse("48 89 05");
        int searchStart = Math.Max(0, referenceOffset - 0x500);
        int worldInstruction = worldStore.Find(module, searchStart, referenceOffset - searchStart);
        if (worldInstruction < 0)
        {
            throw new InvalidDataException("The Unreal world pointer store was not found near its anchor.");
        }
        int worldDisplacement = BinaryPrimitives.ReadInt32LittleEndian(
            module.Slice(worldInstruction + 3, sizeof(int)));
        long worldPointer = checked(memory.ModuleBase + worldInstruction + 7L + worldDisplacement);
        if (!ProcessMemory.IsCanonicalPointer(worldPointer))
        {
            throw new InvalidDataException("The Unreal world pointer resolved outside user memory.");
        }

        return new UnrealGlobals(namePool, worldPointer);
    }

    internal static long ResolveRipRelative(long instructionAddress, int instructionLength, int displacement) =>
        checked(instructionAddress + instructionLength + displacement);

    private static int FindRipRelativeReference(
        ReadOnlySpan<byte> module,
        long moduleBase,
        long targetAddress)
    {
        for (int index = 0; index <= module.Length - 7; index++)
        {
            byte rex = module[index];
            if ((rex is not 0x48 and not 0x4C) || module[index + 1] != 0x8D)
            {
                continue;
            }
            byte modRm = module[index + 2];
            if ((modRm & 0xC7) != 0x05)
            {
                continue;
            }
            int displacement = BinaryPrimitives.ReadInt32LittleEndian(module.Slice(index + 3, 4));
            long resolved = ResolveRipRelative(moduleBase + index, 7, displacement);
            if (resolved == targetAddress)
            {
                return index;
            }
        }
        return -1;
    }
}

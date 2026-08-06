using System.Diagnostics;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
using PalworldLiveMap.Reader.Interop;

namespace PalworldLiveMap.Reader.Memory;

internal sealed class ProcessMemory : IDisposable
{
    private const long MinimumPointer = 0x10000;
    private const long MaximumUserPointer = 0x0000_7FFF_FFFF_FFFF;
    private readonly SafeProcessHandle _handle;

    private ProcessMemory(Process process, SafeProcessHandle handle, long moduleBase, int moduleSize)
    {
        Process = process;
        _handle = handle;
        ModuleBase = moduleBase;
        ModuleSize = moduleSize;
    }

    internal Process Process { get; }
    internal long ModuleBase { get; }
    internal int ModuleSize { get; }

    internal static ProcessMemory Attach(Process process)
    {
        ArgumentNullException.ThrowIfNull(process);
        if (process.HasExited)
        {
            throw new InvalidOperationException("Palworld exited before the reader could attach.");
        }

        SafeProcessHandle handle = NativeMethods.OpenProcess(
            ProcessAccess.QueryInformation | ProcessAccess.VirtualMemoryRead,
            inheritHandle: false,
            process.Id);
        if (handle.IsInvalid)
        {
            handle.Dispose();
            throw NativeMethods.LastError("OpenProcess failed");
        }

        try
        {
            ProcessModule module = process.MainModule
                ?? throw new InvalidOperationException("Palworld's main module is unavailable.");
            long moduleBase = module.BaseAddress.ToInt64();
            int moduleSize = module.ModuleMemorySize;
            if (!IsCanonicalPointer(moduleBase) || moduleSize <= 0)
            {
                throw new InvalidOperationException("Palworld reported an invalid main-module range.");
            }
            return new ProcessMemory(process, handle, moduleBase, moduleSize);
        }
        catch
        {
            handle.Dispose();
            throw;
        }
    }

    internal unsafe void ReadExactly(long address, Span<byte> destination)
    {
        if (!IsCanonicalPointer(address))
        {
            throw new InvalidDataException($"Rejected non-canonical address 0x{address:X}.");
        }
        if (destination.Length == 0)
        {
            return;
        }

        fixed (byte* buffer = destination)
        {
            bool read = NativeMethods.ReadProcessMemory(
                _handle,
                (nint)address,
                buffer,
                (nuint)destination.Length,
                out nuint bytesRead);
            if (!read || bytesRead != (nuint)destination.Length)
            {
                throw NativeMethods.LastError(
                    $"ReadProcessMemory failed at 0x{address:X} " +
                    $"({bytesRead}/{destination.Length} bytes)");
            }
        }
    }

    internal byte[] ReadBytes(long address, int length)
    {
        if (length < 0)
        {
            throw new ArgumentOutOfRangeException(nameof(length));
        }
        var bytes = new byte[length];
        ReadExactly(address, bytes);
        return bytes;
    }

    internal short ReadInt16(long address)
    {
        Span<byte> bytes = stackalloc byte[sizeof(short)];
        ReadExactly(address, bytes);
        return MemoryMarshal.Read<short>(bytes);
    }

    internal byte ReadByte(long address)
    {
        Span<byte> bytes = stackalloc byte[1];
        ReadExactly(address, bytes);
        return bytes[0];
    }

    internal ushort ReadUInt16(long address)
    {
        Span<byte> bytes = stackalloc byte[sizeof(ushort)];
        ReadExactly(address, bytes);
        return MemoryMarshal.Read<ushort>(bytes);
    }

    internal int ReadInt32(long address)
    {
        Span<byte> bytes = stackalloc byte[sizeof(int)];
        ReadExactly(address, bytes);
        return MemoryMarshal.Read<int>(bytes);
    }

    internal long ReadInt64(long address)
    {
        Span<byte> bytes = stackalloc byte[sizeof(long)];
        ReadExactly(address, bytes);
        return MemoryMarshal.Read<long>(bytes);
    }

    internal double ReadDouble(long address)
    {
        Span<byte> bytes = stackalloc byte[sizeof(double)];
        ReadExactly(address, bytes);
        return MemoryMarshal.Read<double>(bytes);
    }

    internal long ReadPointer(long address)
    {
        long pointer = ReadInt64(address);
        if (pointer != 0 && !IsCanonicalPointer(pointer))
        {
            throw new InvalidDataException(
                $"Address 0x{address:X} contained non-canonical pointer 0x{pointer:X}.");
        }
        return pointer;
    }

    internal byte[] ReadModuleImage() => ReadBytes(ModuleBase, ModuleSize);

    internal static bool IsCanonicalPointer(long value) =>
        value >= MinimumPointer && value <= MaximumUserPointer;

    public void Dispose()
    {
        _handle.Dispose();
        Process.Dispose();
    }
}

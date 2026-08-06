using System.ComponentModel;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

namespace PalworldLiveMap.Reader.Interop;

[Flags]
internal enum ProcessAccess : uint
{
    VirtualMemoryRead = 0x0010,
    QueryInformation = 0x0400,
}

internal static partial class NativeMethods
{
    [LibraryImport("kernel32.dll", SetLastError = true)]
    internal static partial SafeProcessHandle OpenProcess(
        ProcessAccess desiredAccess,
        [MarshalAs(UnmanagedType.Bool)] bool inheritHandle,
        int processId);

    [LibraryImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static unsafe partial bool ReadProcessMemory(
        SafeProcessHandle process,
        nint baseAddress,
        byte* buffer,
        nuint size,
        out nuint bytesRead);

    internal static Win32Exception LastError(string operation) =>
        new(Marshal.GetLastPInvokeError(), operation);
}

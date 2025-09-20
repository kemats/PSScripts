<#
.SYNOPSIS
    Resolves the symbol name for a given DLL path and offset using dbghelp.dll.

.DESCRIPTION
    This script resolves the symbol name for a given DLL path and offset using dbghelp.dll.
    For example, application event log of source "Application Error" and event ID 1000 may contain faulting module and offset information for crashes.
    You can use this script to resolve the symbol name for the given module and offset.
    Please note that you need to perform this script with appropriate bitness of PowerShell (x86/x64) matching the target DLL.
    Symbol load diagnostics will be logged to a temporary file beginning with "dbghelp_" in the system temp directory.

.PARAMETER dllPath
    DLL path for symbol resolution you want to perform.

.PARAMETER offset
    Offset within the DLL for symbol resolution.

.OUTPUTS
    System.String - Resolved symbol name with offset. E.g. "module_name!function_name+0x123"

.EXAMPLE
    ./Resolve-Symbol.ps1 -dllPath "C:\Windows\System32\ucrtbase.dll" -offset 0x00000000000a4ace
#>
param (
    [Parameter(Mandatory=$true)][string]$dllPath,
    [Parameter(Mandatory=$true)][UInt64]$offset
)


$symbolResolverSource = @"
    using System;
    using System.ComponentModel;
    using System.Diagnostics;
    using System.IO;
    using System.Runtime.InteropServices;

    public class SymbolResolver
    {

        //private const string dbghelpPath = @"C:\Program Files (x86)\Windows Kits\10\Debuggers\x64\dbghelp.dll";
        private const string dbghelpPath = @"dbghelp.dll";

        [DllImport("kernel32.dll", SetLastError = true)]
        static extern IntPtr OpenProcess(uint dwDesiredAccess, bool bInheritHandle, uint dwProcessId);

        [DllImport(dbghelpPath, SetLastError = true)]
        public static extern bool SymInitialize(IntPtr hProcess, string UserSearchPath, bool fInvadeProcess);

        [DllImport(dbghelpPath, SetLastError = true)]
        public static extern bool SymCleanup(IntPtr hProcess);

        [DllImport(dbghelpPath, SetLastError = true)]
        public static extern ulong SymLoadModuleEx(
            IntPtr hProcess,
            IntPtr hFile,
            string ImageName,
            string ModuleName,
            ulong BaseOfDll,
            uint DllSize,
            IntPtr Data,
            uint Flags);

        [DllImport(dbghelpPath, SetLastError = true)]
        public static extern bool SymFromAddr(
            IntPtr hProcess,
            ulong Address,
            out ulong Displacement,
            IntPtr Symbol);

        private const int SYMBOL_NAME_MAX_LENGTH = 1024;

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
        public struct SYMBOL_INFO
        {
            public uint SizeOfStruct;
            public uint TypeIndex;
            public ulong Reserved1;
            public ulong Reserved2;
            public uint Index;
            public uint Size;
            public ulong ModBase;
            public uint Flags;
            public ulong Value;
            public ulong Address;
            public uint Register;
            public uint Scope;
            public uint Tag;
            public uint NameLen;
            public uint MaxNameLen;

            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = SYMBOL_NAME_MAX_LENGTH)]
            public string Name;
        }

        public static string ResolveSymbol(string dllPath, ulong offset)
        {
            var logPath = Path.Combine(Path.GetTempPath(), string.Format("dbghelp_{0:yyyyMMddHHmmss}.log", DateTime.Now));
            Environment.SetEnvironmentVariable("DBGHELP_LOG", logPath, EnvironmentVariableTarget.Process);

            IntPtr hCurrentProcess = Process.GetCurrentProcess().Handle;
            if (!SymInitialize(hCurrentProcess, null, false))
            {
                throw new Win32Exception();
            }

            ulong moduleBase = SymLoadModuleEx(hCurrentProcess, IntPtr.Zero, dllPath, null, 0, 0, IntPtr.Zero, 0);
            if (moduleBase == 0)
            {
                var ex = new Win32Exception(); 
                SymCleanup(hCurrentProcess);
                throw ex;
            }
            
            SYMBOL_INFO symbol = new SYMBOL_INFO();
            symbol.MaxNameLen = SYMBOL_NAME_MAX_LENGTH;
            symbol.SizeOfStruct = (uint)Marshal.SizeOf(typeof(SYMBOL_INFO)) - symbol.MaxNameLen;

            IntPtr symbolPtr = Marshal.AllocHGlobal(Marshal.SizeOf(symbol));
            Marshal.StructureToPtr(symbol, symbolPtr, false);

            ulong displacement;
            bool result = SymFromAddr(hCurrentProcess, moduleBase + offset, out displacement, symbolPtr);
            if (!result)
            {
                var ex = new Win32Exception(); 
                Marshal.FreeHGlobal(symbolPtr);
                SymCleanup(hCurrentProcess);
                throw ex;
            }

            SYMBOL_INFO resolved = Marshal.PtrToStructure<SYMBOL_INFO>(symbolPtr);
            Marshal.FreeHGlobal(symbolPtr);
            SymCleanup(hCurrentProcess);

            return string.Format("{0}!{1}+0x{2:x}", 
                Path.GetFileNameWithoutExtension(dllPath).ToLower(), 
                resolved.Name, 
                (moduleBase + offset) - resolved.Address);
        }
    }
"@

if (-not ("SymbolResolver" -as [type])) {
    Add-Type -TypeDefinition $symbolResolverSource
}

return [SymbolResolver]::ResolveSymbol($dllPath, $offset)
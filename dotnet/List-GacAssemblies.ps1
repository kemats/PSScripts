# List assemblies in the Global Assembly Cache (GAC) like "gacutil.exe /l" by calling the following Fusion APIs.
# https://learn.microsoft.com/en-us/dotnet/framework/unmanaged-api/fusion/createassemblyenum-function
# https://learn.microsoft.com/en-us/dotnet/framework/unmanaged-api/fusion/iassemblyenum-interface 
# https://learn.microsoft.com/en-us/dotnet/framework/unmanaged-api/fusion/iassemblyname-interface
# https://learn.microsoft.com/en-us/dotnet/framework/unmanaged-api/fusion/asm-display-flags-enumeration
$source = @"
   using Microsoft.Win32;
   using System;
   using System.Collections.Generic;
   using System.ComponentModel;
   using System.Diagnostics;
   using System.IO;
   using System.Runtime.InteropServices;
   using System.Text;
 
   public class FusionAPi
   {
       [ComImport, InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
       [Guid("21b8916c-f28e-11d2-a473-00c04f8ef448")]
       internal interface IAssemblyEnum
       {
           [PreserveSig]
           int GetNextAssembly(IntPtr pvReserved, out IAssemblyName ppName, int flags);
           int Reset();
           int Clone(out IAssemblyEnum ppEnum);
       }
 
       [ComImport, InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
       [Guid("CD193BC0-B4BC-11d2-9833-00C04FC31D2E")]
       internal interface IAssemblyName
       {
           int SetProperty(int PropertyId, IntPtr pvProperty, int cbProperty);
           int GetProperty(int PropertyId, IntPtr pvProperty, ref int pcbProperty);
           int Finalize();
           [PreserveSig]
           int GetDisplayName(StringBuilder pDisplayName, ref int pccDisplayName, int displayFlags);
           int Reserved(ref Guid guid, Object obj1, Object obj2, String string1, Int64 llFlags, IntPtr pvReserved, int cbReserved, out IntPtr ppv);
           [PreserveSig]
           int GetName(ref int pccBuffer, StringBuilder pwzName);
           int GetVersion(out int versionHi, out int versionLow);
           int IsEqual(IAssemblyName pAsmName, int cmpFlags);
           int Clone(out IAssemblyName pAsmName);
       }
 
       [UnmanagedFunctionPointer(CallingConvention.Winapi, CharSet = CharSet.Unicode)]
       private delegate int CreateAssemblyEnumDelegate(out IAssemblyEnum ppEnum, IntPtr pUnkReserved, IAssemblyName pName, int flags, IntPtr pvReserved);
 
       [DllImport("kernel32.dll", SetLastError=true)]
       private static extern IntPtr LoadLibrary(string lpFileName);
 
       [DllImport("kernel32.dll", SetLastError=true)]
       private static extern IntPtr GetProcAddress(IntPtr hModule, [MarshalAs(UnmanagedType.LPStr)] string procName);
 
       [DllImport("kernel32.dll")]
       [return: MarshalAs(UnmanagedType.Bool)]
       private static extern bool FreeLibrary(IntPtr hModule);
 
       public static List<string> GetGacAssemblies()
       {
           RegistryKey regKeyNetFx = Registry.LocalMachine.OpenSubKey(@"Software\Microsoft\.NETFramework", false);
           string installRoot = Path.Combine(regKeyNetFx.GetValue("InstallRoot").ToString(), "v4.0.30319");
           string fusionDllPath = Path.Combine(installRoot, "fusion.dll");
           IntPtr hModule = LoadLibrary(fusionDllPath);
           if (hModule == IntPtr.Zero)
           {
               throw new Win32Exception(fusionDllPath);
           }
 
           List<string> result = new List<string>();
           try
           {
               if (hModule != IntPtr.Zero)
               {
                   const string procName = "CreateAssemblyEnum";
                   IntPtr pfnCreateAssemblyEnum = GetProcAddress(hModule, procName);
                   if (pfnCreateAssemblyEnum == IntPtr.Zero)
                   {
                       throw new Win32Exception(procName);
                   }

                   var d = (CreateAssemblyEnumDelegate)Marshal.GetDelegateForFunctionPointer(pfnCreateAssemblyEnum, typeof(CreateAssemblyEnumDelegate));
 
                   IAssemblyEnum assemblyEnum = null;
                   int hr = d(out assemblyEnum, IntPtr.Zero, null, 2 /* AssemblyCacheFalgs.Gac */, IntPtr.Zero);
                   if (hr < 0)
                   {
                       Marshal.ThrowExceptionForHR(hr);
                   }

                   IAssemblyName assemblyName = null;
                   while (assemblyEnum.GetNextAssembly(IntPtr.Zero, out assemblyName, 0) >= 0 && assemblyName != null)
                   {
                       // ASM_DISPLAYF_VERSION | ASM_DISPLAYF_CULTURE | ASM_DISPLAYF_PUBLIC_KEY_TOKEN | ASM_DISPLAYF_PROCESSORARCHITECTURE | ASM_DISPLAYF_RETARGET
                       const int displayFlag = 0xA7;
                       int bufferSize = 0;
                       StringBuilder buffer = null;
                       assemblyName.GetDisplayName(buffer, ref bufferSize, displayFlag);
                       buffer = new StringBuilder(bufferSize);
                       assemblyName.GetDisplayName(buffer, ref bufferSize, displayFlag);
                       result.Add(buffer.ToString());
                   }
               }
           }
           finally
           {
               FreeLibrary(hModule);
           }
           return result;
       }
   }
"@
Add-Type -Language CSharp -TypeDefinition $source
[FusionApi]::GetGacAssemblies()
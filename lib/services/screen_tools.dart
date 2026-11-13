// Les yeux et la main de Fractus sur l'écran : capture (avec une grille de
// coordonnées pour que le modèle vision se repère), souris (clic, double-clic,
// clic droit, déplacement, molette, glisser), fenêtres (déplacer, redimensionner,
// réduire, agrandir, fermer). Tout passe par PowerShell + user32, en pixels
// physiques (SetProcessDPIAware dans chaque script, pour que capture et clics
// parlent le même repère).

import 'dart:convert';
import 'dart:io';

/// Prélude commun : user32 et DPI.
const String psNative = r'''
Add-Type -TypeDefinition @"
using System; using System.Runtime.InteropServices;
public static class FxNative {
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint data, UIntPtr extra);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr h, int x, int y, int w, int hh, bool repaint);
  [DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr h, int n);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  public struct POINT { public int X; public int Y; }
  public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
}
"@
[FxNative]::SetProcessDPIAware() | Out-Null
''';

String psQuote(String s) => "'${s.replaceAll("'", "''")}'";

/// Capture (tout l'écran, ou une région) en JPEG réduit, avec une grille tous
/// les 100 px annotée en coordonnées écran. Renvoie le script ; la sortie est
/// un JSON {path, x, y, width, height, scale}.
String psScreenshot({
  required String path,
  int? x,
  int? y,
  int? width,
  int? height,
  bool grid = true,
  int maxWidth = 1400,
  int quality = 72,
}) {
  final region = (x != null && y != null && width != null && height != null)
      ? '\$rx=$x; \$ry=$y; \$rw=$width; \$rh=$height'
      : '\$b=[System.Windows.Forms.SystemInformation]::VirtualScreen; \$rx=\$b.Left; \$ry=\$b.Top; \$rw=\$b.Width; \$rh=\$b.Height';
  return '''
$psNative
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
$region
if (\$rw -lt 8 -or \$rh -lt 8) { '{"error":"Région trop petite"}'; exit 0 }
\$bmp = New-Object System.Drawing.Bitmap \$rw, \$rh
\$g = [System.Drawing.Graphics]::FromImage(\$bmp)
\$g.CopyFromScreen(\$rx, \$ry, 0, 0, \$bmp.Size)
if (${grid ? '\$true' : '\$false'}) {
  \$step = 100
  \$pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(110, 56, 189, 248)), 1
  \$font = New-Object System.Drawing.Font 'Segoe UI', 13, [System.Drawing.FontStyle]::Bold
  \$bg = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(170, 0, 0, 0))
  \$fg = [System.Drawing.Brushes]::White
  \$gx = \$step - ((\$rx % \$step + \$step) % \$step)
  for (\$i = \$gx; \$i -lt \$rw; \$i += \$step) {
    \$g.DrawLine(\$pen, \$i, 0, \$i, \$rh)
    \$label = [string](\$rx + \$i)
    \$sz = \$g.MeasureString(\$label, \$font)
    \$g.FillRectangle(\$bg, \$i + 2, 2, \$sz.Width, \$sz.Height)
    \$g.DrawString(\$label, \$font, \$fg, \$i + 2, 2)
  }
  \$gy = \$step - ((\$ry % \$step + \$step) % \$step)
  for (\$j = \$gy; \$j -lt \$rh; \$j += \$step) {
    \$g.DrawLine(\$pen, 0, \$j, \$rw, \$j)
    \$label = [string](\$ry + \$j)
    \$sz = \$g.MeasureString(\$label, \$font)
    \$g.FillRectangle(\$bg, 2, \$j + 2, \$sz.Width, \$sz.Height)
    \$g.DrawString(\$label, \$font, \$fg, 2, \$j + 2)
  }
}
\$scale = 1.0
\$out = \$bmp
if (\$rw -gt $maxWidth) {
  \$scale = $maxWidth / \$rw
  \$out = New-Object System.Drawing.Bitmap ([int](\$rw * \$scale)), ([int](\$rh * \$scale))
  \$g2 = [System.Drawing.Graphics]::FromImage(\$out)
  \$g2.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  \$g2.DrawImage(\$bmp, 0, 0, \$out.Width, \$out.Height)
  \$g2.Dispose()
}
\$codec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { \$_.MimeType -eq 'image/jpeg' }
\$params = New-Object System.Drawing.Imaging.EncoderParameters 1
\$params.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter ([System.Drawing.Imaging.Encoder]::Quality), [long]$quality
\$out.Save(${psQuote(path)}, \$codec, \$params)
\$g.Dispose(); if (\$out -ne \$bmp) { \$out.Dispose() }; \$bmp.Dispose()
@{ path=${psQuote(path)}; x=\$rx; y=\$ry; width=\$rw; height=\$rh; scale=\$scale } | ConvertTo-Json -Compress
''';
}

/// Souris : `button` left|right|middle ; `clicks` 1 ou 2.
String psClick(int x, int y, {String button = 'left', int clicks = 1}) {
  final (down, up) = switch (button) {
    'right' => (0x0008, 0x0010),
    'middle' => (0x0020, 0x0040),
    _ => (0x0002, 0x0004),
  };
  return '''
$psNative
[FxNative]::SetCursorPos($x, $y) | Out-Null
Start-Sleep -Milliseconds 60
for (\$i = 0; \$i -lt $clicks; \$i++) {
  [FxNative]::mouse_event($down, 0, 0, 0, [UIntPtr]::Zero)
  Start-Sleep -Milliseconds 40
  [FxNative]::mouse_event($up, 0, 0, 0, [UIntPtr]::Zero)
  if ($clicks -gt 1) { Start-Sleep -Milliseconds 90 }
}
'{"ok":true,"x":$x,"y":$y}'
''';
}

String psMoveMouse(int x, int y) => '''
$psNative
[FxNative]::SetCursorPos($x, $y) | Out-Null
'{"ok":true,"x":$x,"y":$y}'
''';

/// Molette : `amount` en crans (positif = vers le haut), `horizontal` pour le défilement latéral.
String psScroll(int x, int y, int amount, {bool horizontal = false}) => '''
$psNative
[FxNative]::SetCursorPos($x, $y) | Out-Null
Start-Sleep -Milliseconds 60
[FxNative]::mouse_event(${horizontal ? 0x1000 : 0x0800}, 0, 0, [uint32](($amount * 120) -band 0xFFFFFFFF), [UIntPtr]::Zero)
'{"ok":true}'
''';

String psDrag(int x1, int y1, int x2, int y2) => '''
$psNative
[FxNative]::SetCursorPos($x1, $y1) | Out-Null
Start-Sleep -Milliseconds 80
[FxNative]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
\$steps = 20
for (\$i = 1; \$i -le \$steps; \$i++) {
  \$px = [int]($x1 + ($x2 - $x1) * \$i / \$steps)
  \$py = [int]($y1 + ($y2 - $y1) * \$i / \$steps)
  [FxNative]::SetCursorPos(\$px, \$py) | Out-Null
  Start-Sleep -Milliseconds 15
}
[FxNative]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
'{"ok":true}'
''';

const String psMousePosition = '''
$psNative
\$p = New-Object FxNative+POINT
[FxNative]::GetCursorPos([ref]\$p) | Out-Null
@{ x=\$p.X; y=\$p.Y } | ConvertTo-Json -Compress
''';

/// Les fenêtres visibles avec leur rectangle écran et si elles sont au premier plan.
const String psWindows = '''
$psNative
\$fg = [FxNative]::GetForegroundWindow()
Get-Process | Where-Object { \$_.MainWindowHandle -ne 0 -and \$_.MainWindowTitle } | ForEach-Object {
  \$r = New-Object FxNative+RECT
  [FxNative]::GetWindowRect(\$_.MainWindowHandle, [ref]\$r) | Out-Null
  @{ title=\$_.MainWindowTitle; process=\$_.ProcessName; pid=\$_.Id; x=\$r.Left; y=\$r.Top; width=(\$r.Right-\$r.Left); height=(\$r.Bottom-\$r.Top); minimized=[FxNative]::IsIconic(\$_.MainWindowHandle); foreground=(\$_.MainWindowHandle -eq \$fg) }
} | ConvertTo-Json -Compress
''';

/// Sélecteur PowerShell d'une fenêtre par titre (contient) ou PID.
String psSelectWindow({String? title, int? pid}) {
  if (pid != null) return 'Get-Process -Id $pid -ErrorAction Stop';
  return 'Get-Process | Where-Object { \$_.MainWindowHandle -ne 0 -and \$_.MainWindowTitle -like (\'*\' + ${psQuote(title ?? '')} + \'*\') } | Select-Object -First 1';
}

/// Action sur une fenêtre : minimize | maximize | restore | close | move (x,y,width,height).
String psWindowAction(String selector, String action, {int? x, int? y, int? width, int? height}) {
  final String body = switch (action) {
    'minimize' => '[FxNative]::ShowWindowAsync(\$h, 6) | Out-Null',
    'maximize' => '[FxNative]::ShowWindowAsync(\$h, 3) | Out-Null; [FxNative]::SetForegroundWindow(\$h) | Out-Null',
    'restore' => '[FxNative]::ShowWindowAsync(\$h, 9) | Out-Null; [FxNative]::SetForegroundWindow(\$h) | Out-Null',
    'close' => '[FxNative]::PostMessage(\$h, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null',
    'move' => '''
\$r = New-Object FxNative+RECT
[FxNative]::GetWindowRect(\$h, [ref]\$r) | Out-Null
[FxNative]::ShowWindowAsync(\$h, 9) | Out-Null
\$nx = ${x ?? '\$r.Left'}; \$ny = ${y ?? '\$r.Top'}; \$nw = ${width ?? '(\$r.Right-\$r.Left)'}; \$nh = ${height ?? '(\$r.Bottom-\$r.Top)'}
[FxNative]::MoveWindow(\$h, \$nx, \$ny, \$nw, \$nh, \$true) | Out-Null''',
    _ => 'throw "Action inconnue"',
  };
  return '''
$psNative
\$p = $selector
if (-not \$p -or \$p.MainWindowHandle -eq 0) { '{"error":"Fenêtre introuvable"}'; exit 0 }
\$h = \$p.MainWindowHandle
$body
Start-Sleep -Milliseconds 150
\$r2 = New-Object FxNative+RECT
[FxNative]::GetWindowRect(\$h, [ref]\$r2) | Out-Null
@{ ok=\$true; title=\$p.MainWindowTitle; pid=\$p.Id; x=\$r2.Left; y=\$r2.Top; width=(\$r2.Right-\$r2.Left); height=(\$r2.Bottom-\$r2.Top) } | ConvertTo-Json -Compress
''';
}

/// Lit le JSON produit par un script de capture et charge l'image.
Future<({Map<String, dynamic> meta, List<int> bytes})?> readShot(String json) async {
  try {
    final j = jsonDecode(json);
    if (j is! Map<String, dynamic> || j['path'] == null) return null;
    final f = File(j['path'] as String);
    if (!await f.exists()) return null;
    return (meta: j, bytes: await f.readAsBytes());
  } catch (_) {
    return null;
  }
}

# 桌面自动化函数，在桌面会话中使用：. Gui.ps1（工具目录已在 PATH 中）
Add-Type @'
using System; using System.Runtime.InteropServices;
public static class W {
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint x, uint y, uint d, UIntPtr e);
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint f, UIntPtr e);
}
'@
[W]::SetProcessDPIAware() | Out-Null
$VK = @{ Enter = 0x0D; Esc = 0x1B; Tab = 0x09; Back = 0x08; Del = 0x2E; Space = 0x20; Up = 0x26; Down = 0x28; Left = 0x25; Right = 0x27
         Ctrl = 0x11; Shift = 0x10; Alt = 0x12; Win = 0x5B; F4 = 0x73; F5 = 0x74 }

function Get-Windows { Get-Process | Where-Object MainWindowTitle | Select-Object ProcessName, Id, MainWindowTitle }

function Focus-Window([string]$Process, [int]$Show = 3) {        # Show: 3 最大化, 9 还原, 6 最小化
  $p = Get-Process $Process -EA SilentlyContinue | Where-Object MainWindowHandle -ne 0 | Select-Object -First 1
  if (-not $p) { throw "找不到窗口: $Process" }
  [W]::ShowWindow($p.MainWindowHandle, $Show) | Out-Null
  [W]::SetForegroundWindow($p.MainWindowHandle) | Out-Null
  Start-Sleep -Milliseconds 400
}

function Click([int]$X, [int]$Y, [switch]$Double, [switch]$Right) {   # 坐标 = 截图原始像素
  $d, $u = if ($Right) { 8, 0x10 } else { 2, 4 }
  [W]::SetCursorPos($X, $Y)
  1..($(if ($Double) { 2 } else { 1 })) | ForEach-Object { [W]::mouse_event($d, 0, 0, 0, [UIntPtr]::Zero); [W]::mouse_event($u, 0, 0, 0, [UIntPtr]::Zero) }
  Start-Sleep -Milliseconds 300
}

function Send-Key([string[]]$Keys) {                             # Send-Key Enter / Send-Key Ctrl,A / Send-Key Win,D
  $c = @($Keys | ForEach-Object { if ($VK.ContainsKey($_)) { $VK[$_] } else { [int][char]$_.ToUpper() } })
  foreach ($k in $c) { [W]::keybd_event([byte]$k, 0, 0, [UIntPtr]::Zero) }
  [array]::Reverse($c)
  foreach ($k in $c) { [W]::keybd_event([byte]$k, 0, 2, [UIntPtr]::Zero) }
  Start-Sleep -Milliseconds 200
}

function Send-Text([string]$Text) {                              # 剪贴板粘贴（支持中文），之后还原剪贴板
  $old = Get-Clipboard -Raw -EA SilentlyContinue
  Set-Clipboard -Value $Text; Send-Key Ctrl, V; Start-Sleep -Milliseconds 300
  if ($null -ne $old) { Set-Clipboard -Value $old }
}

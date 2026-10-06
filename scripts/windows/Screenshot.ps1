# 在已登录的桌面会话里截全屏，保存到当前目录的 .ai-shots\<Name>.png（会同步回 Mac）
param([string]$Name = "shot-$(Get-Date -Format yyyyMMdd-HHmmss)")
$ErrorActionPreference = 'Stop'
$me  = [Security.Principal.WindowsIdentity]::GetCurrent().Name
$dir = Join-Path (Get-Location).Path '.ai-shots'; New-Item -ItemType Directory -Force $dir | Out-Null
$out = Join-Path $dir "$Name.png"; Remove-Item -LiteralPath $out -EA SilentlyContinue
$body = @"
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type 'using System.Runtime.InteropServices; public class Dpi { [DllImport("user32.dll")] public static extern bool SetProcessDPIAware(); }'
[Dpi]::SetProcessDPIAware() | Out-Null
`$b = [System.Windows.Forms.SystemInformation]::VirtualScreen
`$bmp = [System.Drawing.Bitmap]::new(`$b.Width, `$b.Height)
[System.Drawing.Graphics]::FromImage(`$bmp).CopyFromScreen(`$b.Left, `$b.Top, 0, 0, `$bmp.Size)
`$bmp.Save('$($out -replace "'", "''")', [System.Drawing.Imaging.ImageFormat]::Png)
"@
$enc  = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($body))
$task = "ai-shot-$PID"
Register-ScheduledTask -TaskName $task -Force `
  -Action    (New-ScheduledTaskAction -Execute "$PSHOME\pwsh.exe" -Argument "-NoProfile -WindowStyle Hidden -EncodedCommand $enc") `
  -Principal (New-ScheduledTaskPrincipal -UserId $me -LogonType Interactive) | Out-Null
Start-ScheduledTask -TaskName $task
for ($i = 0; $i -lt 40 -and -not (Test-Path -LiteralPath $out); $i++) { Start-Sleep -Milliseconds 250 }
Start-Sleep -Milliseconds 300
Unregister-ScheduledTask -TaskName $task -Confirm:$false
if (Test-Path -LiteralPath $out) { ".ai-shots/$Name.png" } else { Write-Error "截图失败：桌面可能处于锁屏状态或未登录" }

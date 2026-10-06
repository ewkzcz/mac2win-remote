# 在已登录的桌面会话里同步执行一段 PowerShell，等待结束并返回输出（用于点击、输入、读取窗口等 GUI 操作）
param([Parameter(Mandatory)][string]$Cmd, [int]$TimeoutSec = 60)
$ErrorActionPreference = 'Stop'
$me   = [Security.Principal.WindowsIdentity]::GetCurrent().Name
$id   = [guid]::NewGuid().ToString('N').Substring(0, 8)
$out  = Join-Path $env:TEMP "ai-ii-$id.log"; $done = "$out.done"
$q = { param($s) $s -replace "'", "''" }
$body = @"
`$env:Path = '$(& $q $PSScriptRoot);' + `$env:Path
Set-Location -LiteralPath '$(& $q (Get-Location).Path)'
try { & { $Cmd } *>&1 | Out-File -LiteralPath '$(& $q $out)' -Encoding utf8 -Width 400 }
catch { "ERROR: `$_" | Out-File -LiteralPath '$(& $q $out)' -Append -Encoding utf8 }
finally { New-Item -ItemType File -Path '$(& $q $done)' -Force | Out-Null }
"@
$enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($body))
$task = "ai-ii-$id"
Register-ScheduledTask -TaskName $task -Force `
  -Action    (New-ScheduledTaskAction -Execute "$PSHOME\pwsh.exe" -Argument "-NoProfile -WindowStyle Hidden -EncodedCommand $enc") `
  -Principal (New-ScheduledTaskPrincipal -UserId $me -LogonType Interactive) | Out-Null
Start-ScheduledTask -TaskName $task
$t = 0; while (-not (Test-Path -LiteralPath $done) -and $t -lt $TimeoutSec * 4) { Start-Sleep -Milliseconds 250; $t++ }
Unregister-ScheduledTask -TaskName $task -Confirm:$false
if (Test-Path -LiteralPath $out) { Get-Content -LiteralPath $out; Remove-Item -LiteralPath $out, $done -EA SilentlyContinue }
if ($t -ge $TimeoutSec * 4) { Write-Error "超时（$TimeoutSec 秒）" }

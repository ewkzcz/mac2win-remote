# sshd 自愈：服务不存在就用现有 sshd.exe 重建，保证自动启动并运行，并确认防火墙规则存在；顺带检查 Syncthing 在不在（只报告）。需管理员权限。
# 用法: Repair-Sshd.ps1              检查并修复一次
#       Repair-Sshd.ps1 -Register    注册计划任务 wr-repair-sshd（SYSTEM，开机 + 每 5 分钟执行一次本脚本）
#       Repair-Sshd.ps1 -Unregister  删除该计划任务
# 日志：C:\ProgramData\wr\repair-sshd.log（超过 200 KB 时只保留后半）。脚本里只用 ASCII 字符串，Windows PowerShell 5.1 也能执行。
param([switch]$Register, [switch]$Unregister)
$task = 'wr-repair-sshd'
if ($Unregister) { Unregister-ScheduledTask -TaskName $task -Confirm:$false -ErrorAction SilentlyContinue; "removed $task"; return }
if ($Register) {
  $ps = if (Test-Path "$env:ProgramFiles\PowerShell\7\pwsh.exe") { "$env:ProgramFiles\PowerShell\7\pwsh.exe" } else { "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" }
  $trg = @((New-ScheduledTaskTrigger -AtStartup),
           (New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 5)))
  Register-ScheduledTask -TaskName $task -Force -Trigger $trg `
    -Action    (New-ScheduledTaskAction -Execute $ps -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"") `
    -Principal (New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest) `
    -Settings  (New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 2) -MultipleInstances IgnoreNew) | Out-Null
  "registered $task"; return
}

$dir = Join-Path $env:ProgramData 'wr'; New-Item -ItemType Directory -Force $dir | Out-Null
$log = Join-Path $dir 'repair-sshd.log'
if ((Test-Path $log) -and (Get-Item $log).Length -gt 200KB) { Get-Content $log -Tail 200 | Set-Content $log }
function Log($m) { $l = "{0:s} {1}" -f (Get-Date), $m; Add-Content $log $l; $l }
$fixed = $false

if (-not (Get-Service sshd -ErrorAction SilentlyContinue)) {
  $exe = @("$env:ProgramFiles\OpenSSH\sshd.exe", "$env:SystemRoot\System32\OpenSSH\sshd.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
  if (-not $exe) { Log 'ERROR sshd service missing and no sshd.exe found'; exit 1 }
  Log "sshd service missing, recreating from $exe"
  sc.exe create sshd binPath= "`"$exe`"" start= auto DisplayName= "OpenSSH SSH Server" | Out-Null
  sc.exe description sshd "SSH protocol based service to provide secure encrypted communications between two untrusted hosts over an insecure network." | Out-Null
  sc.exe sidtype sshd unrestricted | Out-Null
  sc.exe failure sshd reset= 86400 actions= restart/60000/restart/60000/restart/60000 | Out-Null
  $fixed = $true
}
$svc = Get-Service sshd
if ($svc.StartType -ne 'Automatic') { Set-Service sshd -StartupType Automatic; Log 'sshd start type set to Automatic'; $fixed = $true }
if ($svc.Status -ne 'Running') {
  Start-Service sshd -ErrorAction SilentlyContinue
  Log ("sshd start attempted, now: " + (Get-Service sshd).Status); $fixed = $true
}
if (-not (Get-NetFirewallRule -Name 'sshd', 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue | Where-Object { $_.Enabled -eq 'True' -and $_.Direction -eq 'Inbound' })) {
  # 与搭建教程一致：只放行 Tailscale 网段
  New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH (Tailscale only)' -Direction Inbound -Protocol TCP -LocalPort 22 -RemoteAddress 100.64.0.0/10 -Action Allow -Profile Any | Out-Null
  Log 'firewall rule OpenSSH-Server-In-TCP created'; $fixed = $true
}
if (-not (Get-Process syncthing -ErrorAction SilentlyContinue)) { Log 'WARN syncthing is not running (report only, not touched)' }
if (-not $fixed) { "ok: sshd $((Get-Service sshd).Status)" }

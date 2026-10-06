# 加固 Windows，避免无人值守时被自动更新重启或睡眠打断长任务。幂等，可重复执行；需管理员权限（wsh 默认即是）。
# 用法: Harden-Windows.ps1            应用并打印每项的 前->后 值
#       Harden-Windows.ps1 -Revert    按首次执行时保存的原值恢复
# 只动下面列出的项，不碰 DNS、代理、防火墙和其他系统设置。原值保存在 C:\ProgramData\wr\harden-backup.json（只在第一次写入）。
param([switch]$Revert)
$ErrorActionPreference = 'Stop'
$dir = Join-Path $env:ProgramData 'wr'; New-Item -ItemType Directory -Force $dir | Out-Null
$bak = Join-Path $dir 'harden-backup.json'
$AU  = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'
$WU  = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
# 注册表项：登录用户在线时不自动重启；固定活动时间 06:00-24:00；不允许"到点强制重启"
$reg = @(
  @($AU, 'NoAutoRebootWithLoggedOnUsers', 1), @($AU, 'AlwaysAutoRebootAtScheduledTime', 0),
  @($WU, 'SetActiveHours', 1), @($WU, 'ActiveHoursStart', 6), @($WU, 'ActiveHoursEnd', 0)
)
# 电源项（交流电下）：睡眠、休眠不超时；合盖不动作（笔记本合盖会睡眠，进程随之冻结）
$pw = @(@('SUB_SLEEP', 'STANDBYIDLE'), @('SUB_SLEEP', 'HIBERNATEIDLE'), @('SUB_BUTTONS', 'LIDACTION'))
# 会触发重启的更新编排计划任务（若存在才处理）
$taskPath = '\Microsoft\Windows\UpdateOrchestrator\'

function Get-Ac($sub, $set) {                  # 输出末尾两个十六进制值依次是 交流 / 直流 当前值
  $m = @(powercfg /query SCHEME_CURRENT $sub $set | Select-String '0x[0-9a-fA-F]+' -AllMatches | ForEach-Object { $_.Matches.Value })
  if ($m.Count -ge 2) { [Convert]::ToInt32($m[-2], 16) }   # 本机没有该设置项时返回 $null，后面跳过
}
function Get-State {
  $s = @{ reg = @{}; power = @{}; tasks = @{} }
  foreach ($r in $reg) { $s.reg["$($r[0])|$($r[1])"] = (Get-ItemProperty $r[0] -Name $r[1] -EA SilentlyContinue).($r[1]) }
  foreach ($p in $pw) { $s.power["$($p[0])|$($p[1])"] = Get-Ac $p[0] $p[1] }
  foreach ($t in Get-ScheduledTask -TaskPath $taskPath -TaskName 'Reboot*' -EA SilentlyContinue) { $s.tasks[$t.TaskName] = [string]$t.State }
  $s
}
$before = Get-State
if (-not $Revert -and -not (Test-Path $bak)) { $before | ConvertTo-Json -Depth 4 | Set-Content $bak -Encoding utf8; "原值已保存: $bak" }

if ($Revert) {
  if (-not (Test-Path $bak)) { throw "没有备份文件: $bak" }
  $o = Get-Content $bak -Raw | ConvertFrom-Json
  foreach ($r in $reg) {
    $v = $o.reg."$($r[0])|$($r[1])"
    if ($null -eq $v) { Remove-ItemProperty $r[0] -Name $r[1] -EA SilentlyContinue } else { Set-ItemProperty $r[0] -Name $r[1] -Value $v -Type DWord }
  }
  foreach ($p in $pw) { if ($null -ne $o.power."$($p[0])|$($p[1])") { powercfg /setacvalueindex SCHEME_CURRENT $p[0] $p[1] ([int]$o.power."$($p[0])|$($p[1])") | Out-Null } }
  powercfg /setactive SCHEME_CURRENT | Out-Null
  foreach ($n in $o.tasks.PSObject.Properties) { if ($n.Value -ne 'Disabled') { Enable-ScheduledTask -TaskPath $taskPath -TaskName $n.Name | Out-Null } }
  'reverted'; return
}

foreach ($r in $reg) {
  if (-not (Test-Path $r[0])) { New-Item $r[0] -Force | Out-Null }
  Set-ItemProperty $r[0] -Name $r[1] -Value $r[2] -Type DWord
}
foreach ($p in $pw) {
  if ($null -eq $before.power["$($p[0])|$($p[1])"]) { continue }
  $v = 0                                                 # 0 = 从不 / 合盖不采取任何操作
  powercfg /setacvalueindex SCHEME_CURRENT $p[0] $p[1] $v | Out-Null
}
powercfg /setactive SCHEME_CURRENT | Out-Null
foreach ($t in Get-ScheduledTask -TaskPath $taskPath -TaskName 'Reboot*' -EA SilentlyContinue) {
  try { Disable-ScheduledTask -TaskPath $taskPath -TaskName $t.TaskName | Out-Null } catch { "无法禁用 $($t.TaskName): $($_.Exception.Message)" }
}

$after = Get-State
"{0,-62} {1,8} -> {2}" -f '项', '原值', '现值'
foreach ($k in $after.reg.Keys)   { "{0,-62} {1,8} -> {2}" -f $k, $before.reg[$k], $after.reg[$k] }
foreach ($k in $after.power.Keys) { "{0,-62} {1,8} -> {2}" -f "powercfg AC $k", $before.power[$k], $after.power[$k] }
foreach ($k in $after.tasks.Keys) { "{0,-62} {1,8} -> {2}" -f "task $k", $before.tasks[$k], $after.tasks[$k] }
if (-not $after.tasks.Count) { '(UpdateOrchestrator 下没有 Reboot* 任务，无需禁用)' }

param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$Cmd)
$ErrorActionPreference = 'Stop'
$me   = [Security.Principal.WindowsIdentity]::GetCurrent().Name
$dir  = (Get-Location).Path
$logs = Join-Path $dir '.ai-logs'; New-Item -ItemType Directory -Force $logs | Out-Null
$log  = Join-Path $logs "$Name.log"; $pidf = Join-Path $logs "$Name.pid"
$q = { param($s) $s -replace "'", "''" }
$body = @"
`$env:Path = '$(& $q $PSScriptRoot);' + `$env:Path
Set-Content -LiteralPath '$(& $q $pidf)' `$PID
Set-Location -LiteralPath '$(& $q $dir)'
& { $Cmd } *>&1 | Tee-Object -FilePath '$(& $q $log)'
"@
$enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($body))
Register-ScheduledTask -TaskName "ai-$Name" -Force `
  -Action    (New-ScheduledTaskAction -Execute "$PSHOME\pwsh.exe" -Argument "-NoProfile -WindowStyle Minimized -EncodedCommand $enc") `
  -Principal (New-ScheduledTaskPrincipal -UserId $me -LogonType Interactive) `
  -Settings  (New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero)) | Out-Null
Start-ScheduledTask -TaskName "ai-$Name"
"started ai-$Name  log: .ai-logs\$Name.log"

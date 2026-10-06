param([Parameter(Mandatory)][string]$Name)
$pidf = Join-Path (Get-Location).Path ".ai-logs\$Name.pid"
if (Test-Path -LiteralPath $pidf) { taskkill /PID (Get-Content -LiteralPath $pidf) /T /F *> $null; Remove-Item -LiteralPath $pidf }
Unregister-ScheduledTask -TaskName "ai-$Name" -Confirm:$false -ErrorAction SilentlyContinue
$global:LASTEXITCODE = 0
"stopped ai-$Name"

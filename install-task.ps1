<#
.SYNOPSIS
  Register (or remove) the scheduled task that keeps serve.ps1 running.

.DESCRIPTION
  Creates a task named "Finnovest edit server" with two triggers:
    - At logon      : starts the server when you log in
    - Every 5 min   : revives it if it ever dies, and after wake from sleep

  serve.ps1 is single-instance - it exits immediately if port 8787 is already
  listening - so the repeating trigger is a no-op while the server is healthy.

  Runs as you, with an interactive logon type, so NO password is stored.
  The trade-off: the server starts at logon rather than at boot.

.EXAMPLE
  .\install-task.ps1
  .\install-task.ps1 -Remove
#>

[CmdletBinding()]
param(
  [string] $TaskName = 'Finnovest edit server',
  [switch] $Remove
)

$ErrorActionPreference = 'Stop'
$script = Join-Path $PSScriptRoot 'serve.ps1'

if ($Remove) {
  try {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction Stop
    Write-Host "`n  Removed '$TaskName'." -ForegroundColor Green
  } catch { Write-Host "`n  No such task: $TaskName" -ForegroundColor Yellow }

  $listener = Get-NetTCPConnection -LocalPort 8787 -State Listen -ErrorAction SilentlyContinue
  if ($listener) {
    Stop-Process -Id $listener.OwningProcess -Force
    Write-Host "  Stopped the running server (pid $($listener.OwningProcess))." -ForegroundColor Green
  }
  exit 0
}

if (-not (Test-Path $script)) { throw "serve.ps1 not found next to this script." }

$action = New-ScheduledTaskAction -Execute 'powershell.exe' `
  -Argument ('-ExecutionPolicy Bypass -NoProfile -WindowStyle Hidden -File "{0}" -Quiet' -f $script)

$tLogon  = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$tRepeat = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) `
             -RepetitionInterval (New-TimeSpan -Minutes 5) `
             -RepetitionDuration (New-TimeSpan -Days 3650)

$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
              -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit ([TimeSpan]::Zero)

$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" `
               -LogonType Interactive -RunLevel Limited

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $tLogon,$tRepeat `
  -Settings $settings -Principal $principal -Force | Out-Null

Write-Host "`n  Registered '$TaskName'." -ForegroundColor Green
Start-ScheduledTask -TaskName $TaskName
Start-Sleep -Seconds 3

try {
  $ping = Invoke-WebRequest -Uri 'http://localhost:8787/ping' -UseBasicParsing -TimeoutSec 10
  Write-Host "  Server responding: $($ping.Content)" -ForegroundColor Green
  Write-Host "`n  Edit at  http://localhost:8787/`n" -ForegroundColor Cyan
} catch {
  Write-Host "  Task registered but the server did not answer on 8787." -ForegroundColor Yellow
  Write-Host "  Check $(Join-Path $PSScriptRoot '.serve\serve.log')" -ForegroundColor Yellow
}

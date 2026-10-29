<#
Schedules the daily encrypted backup on Windows (Task Scheduler) through WSL.
Usage (PowerShell as Administrator):  .\install-backup-schedule.ps1 -Time 21:00
It only registers the task; it does not run a backup or change any data.
Destinations (Windows folder, USB drive) are listed in deploy/trial/backup-targets.
#>
param(
    [string]$Time = "21:00",
    [string]$Distro = "Ubuntu",
    [string]$TrialDir = "~/qadisiyah/deploy/trial"
)
$ErrorActionPreference = "Stop"
$command = "cd $TrialDir && bash auto-backup.sh"
$action = New-ScheduledTaskAction -Execute "wsl.exe" -Argument "-d $Distro -- bash -lc `"$command`""
$trigger = New-ScheduledTaskTrigger -Daily -At $Time
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -DontStopIfGoingOnBatteries
Register-ScheduledTask -TaskName "Qadisiyah Backup" -Action $action -Trigger $trigger -Settings $settings `
    -Description "Daily encrypted Qadisiyah backup to the Windows folder and USB drive" -Force | Out-Null
Write-Host "Daily backup scheduled at $Time."
Write-Host "To test now: Start-ScheduledTask -TaskName 'Qadisiyah Backup'"

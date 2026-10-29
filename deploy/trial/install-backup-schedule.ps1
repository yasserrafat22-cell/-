<#
Schedules the daily encrypted backup on Windows (Task Scheduler) through WSL.
Usage (PowerShell as Administrator):  .\install-backup-schedule.ps1 -Time 21:00
It only registers the task; it does not run a backup or change any data.
Destinations (Windows folder, USB drive) are listed in deploy/trial/backup-targets.
With -UsbFolder (e.g. E:\QadisiyahBackups) a second step copies the newest encrypted file
to the USB stick from Windows; a missing stick is logged and skipped.
#>
param(
    [string]$Time = "21:00",
    [string]$Distro = "Ubuntu",
    [string]$TrialDir = "~/qadisiyah/deploy/trial",
    [string]$WindowsFolder = "C:\QadisiyahBackups",
    [string]$UsbFolder = ""
)
$ErrorActionPreference = "Stop"
$command = "cd $TrialDir && bash auto-backup.sh"
$action = New-ScheduledTaskAction -Execute "wsl.exe" -Argument "-d $Distro -- bash -lc `"$command`""
$actions = @($action)
if ($UsbFolder) {
    $copy = Join-Path $PSScriptRoot "copy-backup-to-usb.ps1"
    $actions += New-ScheduledTaskAction -Execute "powershell.exe" `
        -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$copy`" -Source `"$WindowsFolder`" -UsbFolder `"$UsbFolder`""
}
$trigger = New-ScheduledTaskTrigger -Daily -At $Time
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -DontStopIfGoingOnBatteries
Register-ScheduledTask -TaskName "Qadisiyah Backup" -Action $actions -Trigger $trigger -Settings $settings `
    -Description "Daily encrypted Qadisiyah backup to the Windows folder and USB drive" -Force | Out-Null
Write-Host "Daily backup scheduled at $Time."
Write-Host "To test now: Start-ScheduledTask -TaskName 'Qadisiyah Backup'"

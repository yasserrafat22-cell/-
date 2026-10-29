# جدولة النسخ الاحتياطي اليومي على Windows (Task Scheduler) عبر WSL.
# الاستخدام (PowerShell كمسؤول): .\install-backup-schedule.ps1 -Time 21:00
# لا يشغّل نسخة الآن ولا يغير أي بيانات؛ يسجّل المهمة فقط.
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
    -Description "نسخة احتياطية مشفرة يومية لسيرفر القادسية إلى مجلد Windows والفلاشة" -Force | Out-Null
Write-Host "تمت جدولة النسخ الاحتياطي يوميًا الساعة $Time."
Write-Host "للتجربة الآن: Start-ScheduledTask -TaskName 'Qadisiyah Backup'"

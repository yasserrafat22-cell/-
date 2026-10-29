<#
Copies the newest encrypted backup to a USB drive from Windows (WSL does not see a USB
stick plugged in after WSL started). Run by the scheduled task after auto-backup.sh.
A missing drive is logged and skipped; it never fails the backup. Keeps the last -Keep copies.
#>
param(
    [Parameter(Mandatory = $true)][string]$Source,
    [Parameter(Mandatory = $true)][string]$UsbFolder,
    [int]$Keep = 14,
    [string]$Log = ""
)
if (-not $Log) { $Log = Join-Path $Source "usb-copy.log" }
function Note([string]$text) {
    $line = "{0:yyyy-MM-dd HH:mm:ss} {1}" -f (Get-Date), $text
    Write-Host $line
    Add-Content -Path $Log -Value $line -Encoding UTF8
}
try {
    $newest = Get-ChildItem -Path $Source -Filter "qadisiyah-*.tar.gpg" -File -ErrorAction Stop |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $newest) { Note "No encrypted backup found in $Source"; exit 0 }
    $drive = Split-Path -Qualifier $UsbFolder
    if (-not (Test-Path "$drive\")) { Note "USB drive $drive not connected; skipped (backup is safe in $Source)"; exit 0 }
    New-Item -ItemType Directory -Path $UsbFolder -Force | Out-Null
    Copy-Item -Path $newest.FullName -Destination $UsbFolder -Force
    Get-ChildItem -Path $UsbFolder -Filter "qadisiyah-*.tar.gpg" -File |
        Sort-Object LastWriteTime -Descending | Select-Object -Skip $Keep | Remove-Item -Force
    Note "Copied $($newest.Name) to $UsbFolder"
} catch {
    Note "USB copy failed: $($_.Exception.Message)"
}
exit 0

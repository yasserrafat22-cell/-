<#
  Stops the Qadisiyah trial server. All data is kept.
  Usage: .\stop-trial.ps1
  Deleting trial data is intentionally not offered here: it needs explicit
  approval and a backup first (see docs/06-update-guide.md).
#>
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
docker compose stop
Write-Host 'Stopped. Data is kept. Start again with: docker compose up -d'

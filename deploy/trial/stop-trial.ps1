<#
  Stops the Qadisiyah trial server.
  .\stop-trial.ps1              keep the trial data
  .\stop-trial.ps1 -DeleteData  delete the trial database completely
#>
param([switch]$DeleteData)
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
if ($DeleteData) { docker compose down -v } else { docker compose down }

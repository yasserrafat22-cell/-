<#
  Qadisiyah trial server - Windows (Docker Desktop).
  Usage (PowerShell, inside deploy\trial):   .\start-trial.ps1
  Optional: .\start-trial.ps1 -IP 192.168.1.50
  With an existing .env the current settings are used unchanged.

  - Generates random secrets in .env on first run (never committed).
  - Starts PostgreSQL + API; the API listens on this PC's Wi-Fi/LAN address only.
  - The database is never exposed on the network.
#>
param([string]$IP)
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw 'Docker Desktop is not installed. Install it from https://www.docker.com/products/docker-desktop/ and run again.'
}
docker info *> $null
if ($LASTEXITCODE -ne 0) { throw 'Docker Desktop is not running. Open Docker Desktop, wait until it is ready, then run again.' }

$envFile = Join-Path $PSScriptRoot '.env'
$existing = Test-Path $envFile
if (-not $IP -and -not $existing) {
    $IP = (Get-NetIPAddress -AddressFamily IPv4 |
        Where-Object {
            $_.IPAddress -notmatch '^(127\.|169\.254\.)' -and
            $_.InterfaceAlias -notmatch 'vEthernet|WSL|Docker|Loopback|VirtualBox|VMware|Bluetooth' -and
            $_.PrefixOrigin -in @('Dhcp', 'Manual')
        } |
        Sort-Object InterfaceMetric |
        Select-Object -First 1).IPAddress
    if (-not $IP) { throw 'Could not detect the LAN address. Run again with -IP <address> (see: ipconfig).' }
}

function New-Secret([int]$Length) {
    $bytes = New-Object byte[] 96
    [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    ([Convert]::ToBase64String($bytes) -replace '[+/=]', '').Substring(0, $Length)
}

if (-not $existing) {
    $lines = @(
        "BIND_ADDRESS=$IP",
        "POSTGRES_PASSWORD=$(New-Secret 32)",
        "JWT_SIGNING_KEY=$(New-Secret 64)",
        "BOOTSTRAP_ADMIN_PASSWORD=$(New-Secret 14)7a"
    )
    [IO.File]::WriteAllText($envFile, ($lines -join "`n") + "`n", (New-Object Text.UTF8Encoding $false))
    icacls $envFile /inheritance:r /grant:r "$($env:USERNAME):(R,W)" *> $null
    Write-Host 'Created .env with new random secrets.'
} elseif ($IP) {
    # Existing setup: secrets are never changed; the address only when -IP is given.
    $content = [IO.File]::ReadAllText($envFile) -replace '(?m)^BIND_ADDRESS=.*$', "BIND_ADDRESS=$IP"
    [IO.File]::WriteAllText($envFile, $content, (New-Object Text.UTF8Encoding $false))
}
$IP = ((Select-String -Path $envFile -Pattern '^BIND_ADDRESS=(.*)$').Matches[0].Groups[1].Value).Trim()

$publicNetwork = Get-NetConnectionProfile -ErrorAction SilentlyContinue |
    Where-Object { $_.NetworkCategory -eq 'Public' }
if ($publicNetwork) {
    Write-Warning "Network '$($publicNetwork.Name)' is set to Public. Set it to Private in Windows Settings > Network so the phone can connect."
}

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
$ruleName = 'Qadisiyah trial server (LAN only)'
if (-not (Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue)) {
    if ($isAdmin) {
        New-NetFirewallRule -DisplayName $ruleName -Direction Inbound -Protocol TCP -LocalPort 5080 `
            -Profile Private -RemoteAddress LocalSubnet -Action Allow | Out-Null
        Write-Host 'Firewall: allowed port 5080 from the local network only (Private profile).'
    } else {
        Write-Host 'Tip: if the phone cannot connect, run this script once as Administrator to allow port 5080 on the local network only.'
    }
}

Write-Host 'Starting the trial server (first run downloads and builds; this can take a few minutes)...'
docker compose up -d --build
if ($LASTEXITCODE -ne 0) { throw 'docker compose failed. See the messages above.' }

$url = "http://${IP}:5080"
$ready = $false
for ($i = 0; $i -lt 90; $i++) {
    try {
        if ((Invoke-WebRequest "$url/health/db" -UseBasicParsing -TimeoutSec 3).StatusCode -eq 200) { $ready = $true; break }
    } catch { }
    Start-Sleep -Seconds 2
}
if (-not $ready) { docker compose logs --tail 50 api; throw 'The server did not become ready.' }

$adminPassword = (Select-String -Path $envFile -Pattern '^BOOTSTRAP_ADMIN_PASSWORD=(.*)$').Matches[0].Groups[1].Value
Write-Host ''
Write-Host '================ Qadisiyah trial server is running ================'
Write-Host "  Server address (type it in the app):  $url"
Write-Host '  Username:                             admin'
Write-Host "  Temporary password (first login):     $adminPassword"
Write-Host '  After the first login the app asks you to choose a new password;'
Write-Host '  the temporary password stops working after that.'
Write-Host '  Stop the server (data is kept):  .\stop-trial.ps1'
Write-Host '==================================================================='

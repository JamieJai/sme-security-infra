<#
.SYNOPSIS
  Apply a per-device Offline Domain Join blob to a Windows PC.

.DESCRIPTION
  This script consumes a djoin.exe /provision blob created by the IT automation
  workflow. The blob is device-specific and sensitive, but it does not require
  the employee to type a domain join credential on the target PC.
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$EmployeeId,

    [Parameter(Mandatory = $true)]
    [string]$ComputerName,

    [string]$DomainName = "toss.lan",
    [string]$BlobPath = "$PSScriptRoot\odj.blob",
    [string[]]$DnsServers = @(),
    [switch]$SkipDnsChange,
    [string]$WazuhManager = "192.168.0.30",
    [string]$WazuhAgentVersion = "4.10.4-1",
    [string]$WazuhAgentGroup = "windows",
    [string]$WazuhMsiPath = "",
    [switch]$SkipWazuhInstall,
    [switch]$NoRestart
)

$ErrorActionPreference = "Stop"

function Assert-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "Run this script from an elevated PowerShell session."
    }
}

function Assert-ComputerName([string]$Name) {
    if ($Name.Length -gt 15 -or $Name -notmatch '^[A-Za-z0-9][A-Za-z0-9-]{0,14}$') {
        throw "ComputerName must be 1-15 characters and contain only letters, numbers, and hyphen."
    }
}

function Install-WazuhAgent {
    if ($SkipWazuhInstall) {
        Write-Host "Wazuh agent installation skipped."
        return
    }

    if ([string]::IsNullOrWhiteSpace($WazuhManager)) {
        throw "WazuhManager must not be empty unless -SkipWazuhInstall is used."
    }

    $service = Get-Service -Name WazuhSvc -ErrorAction SilentlyContinue
    if (-not $service) {
        $msiPath = $WazuhMsiPath
        if ([string]::IsNullOrWhiteSpace($msiPath)) {
            $downloadDir = Join-Path $env:ProgramData "Toss\Wazuh"
            New-Item -ItemType Directory -Path $downloadDir -Force | Out-Null
            $msiPath = Join-Path $downloadDir "wazuh-agent-$WazuhAgentVersion.msi"
            if (-not (Test-Path -LiteralPath $msiPath)) {
                $url = "https://packages.wazuh.com/4.x/windows/wazuh-agent-$WazuhAgentVersion.msi"
                Write-Host "Downloading Wazuh agent from $url"
                Invoke-WebRequest -Uri $url -OutFile $msiPath -UseBasicParsing
            }
        }

        if (-not (Test-Path -LiteralPath $msiPath)) {
            throw "Wazuh MSI was not found: $msiPath"
        }

        Write-Host "Installing Wazuh agent for manager $WazuhManager as $ComputerName"
        $arguments = "/i `"$msiPath`" /qn WAZUH_MANAGER=`"$WazuhManager`" WAZUH_REGISTRATION_SERVER=`"$WazuhManager`" WAZUH_AGENT_NAME=`"$ComputerName`" WAZUH_AGENT_GROUP=`"$WazuhAgentGroup`""
        $process = Start-Process -FilePath msiexec.exe -ArgumentList $arguments -Wait -PassThru
        if ($process.ExitCode -notin @(0, 3010)) {
            throw "Wazuh agent installer failed with exit code $($process.ExitCode)."
        }
    }
    else {
        Write-Host "Wazuh agent service already exists. Ensuring it is running."
    }

    Start-Service -Name WazuhSvc -ErrorAction Stop
    Start-Sleep -Seconds 3
    $service = Get-Service -Name WazuhSvc -ErrorAction Stop
    if ($service.Status -ne 'Running') {
        throw "WazuhSvc is not running after installation. Current status: $($service.Status)."
    }
    Write-Host "Wazuh agent service is running."
}

Assert-Administrator
Assert-ComputerName -Name $ComputerName

if ($DnsServers.Count -eq 1 -and $DnsServers[0] -match ',') {
    $DnsServers = $DnsServers[0].Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ }
}

$djoin = Join-Path $env:SystemRoot "System32\djoin.exe"
if (-not (Test-Path -LiteralPath $djoin)) {
    throw "djoin.exe was not found at $djoin."
}

if (-not (Test-Path -LiteralPath $BlobPath)) {
    throw "ODJ blob was not found: $BlobPath"
}

$computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem
if ($computerSystem.PartOfDomain) {
    throw "This PC is already joined to domain $($computerSystem.Domain)."
}

Write-Host "Employee ID: $EmployeeId"
Write-Host "Target domain: $DomainName"
Write-Host "Target computer name: $ComputerName"
Write-Host "ODJ blob: $BlobPath"

if (-not $SkipDnsChange -and $DnsServers.Count -gt 0) {
    $adapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' }
    foreach ($adapter in $adapters) {
        Write-Host "Setting DNS servers on adapter $($adapter.Name): $($DnsServers -join ', ')"
        Set-DnsClientServerAddress -InterfaceIndex $adapter.InterfaceIndex -ServerAddresses $DnsServers
    }
}
else {
    Write-Host "DNS change skipped. Ensure this PC can reach AD DNS before the first domain login."
}

try {
    Resolve-DnsName -Name $DomainName -ErrorAction Stop | Out-Null
    Write-Host "DNS resolution check passed for $DomainName."
}
catch {
    Write-Warning "DNS resolution failed for $DomainName. ODJ can still be applied, but domain login may fail after reboot until DNS is corrected."
}

Install-WazuhAgent

& $djoin /requestODJ /loadfile $BlobPath /windowspath $env:SystemRoot /localos
if ($LASTEXITCODE -ne 0) {
    throw "djoin.exe /requestODJ failed with exit code $LASTEXITCODE."
}

Write-Host "Offline Domain Join request applied. A restart is required."

if (-not $NoRestart) {
    Restart-Computer -Force
}
else {
    Write-Host "Restart skipped because -NoRestart was set."
}

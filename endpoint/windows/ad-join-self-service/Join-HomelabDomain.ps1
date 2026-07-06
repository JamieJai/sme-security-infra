<#
.SYNOPSIS
  Join a Windows PC to the homelab AD domain using the employee's AD credential.

.DESCRIPTION
  This script is intended to be downloaded from the IT onboarding portal with an
  employee id parameter embedded in the launcher. It does not contain domain join
  secrets. The employee or IT staff must run it in an elevated PowerShell session
  and provide valid AD credentials when prompted.

  For a more controlled no-password-download process, use Offline Domain Join
  (djoin.exe) and deliver a per-device blob from a protected portal.
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$EmployeeId,

    [string]$DomainName = "toss.lan",
    [string]$DomainNetbiosName = "TOSS",
    [string]$ComputerName = "",
    [string[]]$DnsServers = @(),
    [switch]$SkipDnsChange,
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

function Get-SafeComputerName([string]$EmployeeId) {
    $normalized = ($EmployeeId.ToUpperInvariant() -replace '[^A-Z0-9-]', '')
    if ($normalized.Length -gt 10) {
        $normalized = $normalized.Substring($normalized.Length - 10)
    }
    return "PC-$normalized"
}

Assert-Administrator

if ([string]::IsNullOrWhiteSpace($ComputerName)) {
    $ComputerName = Get-SafeComputerName -EmployeeId $EmployeeId
}

Write-Host "Employee ID: $EmployeeId"
Write-Host "Target domain: $DomainName"
Write-Host "Target computer name: $ComputerName"

if (-not $SkipDnsChange -and $DnsServers.Count -gt 0) {
    $adapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' }
    foreach ($adapter in $adapters) {
        Write-Host "Setting DNS servers on adapter $($adapter.Name): $($DnsServers -join ', ')"
        Set-DnsClientServerAddress -InterfaceIndex $adapter.InterfaceIndex -ServerAddresses $DnsServers
    }
}
else {
    Write-Host "DNS change skipped. Ensure this PC resolves $DomainName through the AD DNS servers before joining."
}

try {
    Resolve-DnsName -Name $DomainName -ErrorAction Stop | Out-Null
    Write-Host "DNS resolution check passed for $DomainName."
}
catch {
    throw "DNS resolution failed for $DomainName. Set AD DNS servers first, then rerun."
}

$credentialMessage = "Enter AD credential allowed to join this PC to $DomainNetbiosName. Example: $DomainNetbiosName\<username>"
$credential = Get-Credential -Message $credentialMessage

$addComputerArgs = @{
    DomainName = $DomainName
    Credential = $credential
    NewName = $ComputerName
    Force = $true
}

if (-not $NoRestart) {
    $addComputerArgs.Restart = $true
}

Add-Computer @addComputerArgs

if ($NoRestart) {
    Write-Host "Domain join command completed. Restart this PC to finish joining the domain."
}

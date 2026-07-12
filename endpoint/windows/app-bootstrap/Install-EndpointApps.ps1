<#
.SYNOPSIS
  Install standard endpoint apps from a small JSON catalog.

.DESCRIPTION
  This bootstrap is intended for IT-controlled execution after domain join:
  an elevated local run, a management task, or a future GPO computer startup
  script. It does not embed administrator credentials.
#>

param(
    [string]$CatalogPath = "$PSScriptRoot\endpoint-app-catalog.json",
    [string]$LogRoot = "$env:ProgramData\Toss\EndpointApps\Logs",
    [switch]$IncludeDisabled,
    [switch]$WhatIfOnly
)

$ErrorActionPreference = "Stop"

function Assert-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "Run this script from an elevated PowerShell session or a computer startup task."
    }
}

function Expand-EndpointPath([string]$Path) {
    return [Environment]::ExpandEnvironmentVariables($Path)
}

function Test-AppDetected($Detection) {
    if ($null -eq $Detection) {
        return $false
    }

    switch ($Detection.type) {
        "path" {
            $path = Expand-EndpointPath -Path $Detection.path
            return Test-Path -LiteralPath $path
        }
        default {
            throw "Unsupported detection type: $($Detection.type)"
        }
    }
}

function Get-WingetPath {
    $cmd = Get-Command winget.exe -ErrorAction SilentlyContinue
    if ($cmd) {
        return $cmd.Source
    }

    $candidate = Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps\winget.exe"
    if (Test-Path -LiteralPath $candidate) {
        return $candidate
    }

    return $null
}

function Install-WingetApp($App) {
    $winget = Get-WingetPath
    if (-not $winget) {
        throw "winget.exe was not found. Use an internally cached installer command for GPO/SYSTEM deployment or install App Installer first."
    }

    $args = @(
        "install",
        "--id", $App.wingetId,
        "--exact",
        "--silent",
        "--accept-package-agreements",
        "--accept-source-agreements"
    )

    Write-Host "Installing $($App.displayName) with winget package $($App.wingetId)."
    if ($WhatIfOnly) {
        Write-Host "WHATIF: $winget $($args -join ' ')"
        return
    }

    & $winget @args
    if ($LASTEXITCODE -ne 0) {
        throw "winget install failed for $($App.id) with exit code $LASTEXITCODE."
    }
}

function Install-CommandApp($App) {
    if (-not $App.command) {
        throw "App $($App.id) has installerType=command but no command value."
    }

    $command = Expand-EndpointPath -Path $App.command
    $arguments = @()
    if ($App.arguments) {
        $arguments = @($App.arguments)
    }

    Write-Host "Installing $($App.displayName) with command installer."
    if ($WhatIfOnly) {
        Write-Host "WHATIF: $command $($arguments -join ' ')"
        return
    }

    $process = Start-Process -FilePath $command -ArgumentList $arguments -Wait -PassThru
    if ($process.ExitCode -ne 0) {
        throw "Command installer failed for $($App.id) with exit code $($process.ExitCode)."
    }
}

Assert-Administrator

if (-not (Test-Path -LiteralPath $CatalogPath)) {
    throw "Catalog file not found: $CatalogPath"
}

New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$transcript = Join-Path $LogRoot "endpoint-apps-$timestamp.log"
Start-Transcript -Path $transcript -Force | Out-Null

try {
    $catalog = Get-Content -LiteralPath $CatalogPath -Raw | ConvertFrom-Json
    if ($catalog.schemaVersion -ne 1) {
        throw "Unsupported catalog schemaVersion: $($catalog.schemaVersion)"
    }

    foreach ($app in $catalog.apps) {
        if (-not $app.enabled -and -not $IncludeDisabled) {
            Write-Host "Skipping disabled app: $($app.id)"
            continue
        }

        if (Test-AppDetected -Detection $app.detection) {
            Write-Host "Already installed: $($app.displayName)"
            continue
        }

        switch ($app.installerType) {
            "winget" { Install-WingetApp -App $app }
            "command" { Install-CommandApp -App $app }
            default { throw "Unsupported installerType for $($app.id): $($app.installerType)" }
        }

        if (-not $WhatIfOnly -and -not (Test-AppDetected -Detection $app.detection)) {
            throw "Install completed but detection still failed for $($app.id)."
        }
    }
}
finally {
    Stop-Transcript | Out-Null
    Write-Host "Log: $transcript"
}

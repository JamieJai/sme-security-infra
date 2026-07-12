<#
.SYNOPSIS
  Configure and optionally run the standard endpoint app bootstrap task.
#>

param(
    [string]$TaskName = 'Toss_EndpointAppBootstrap',
    [string]$TaskPath = '\',
    [string]$BootstrapScript = '\\storage01\endpoint-apps\Install-EndpointApps.ps1',
    [string]$LogRoot = 'C:\ProgramData\Toss\EndpointApps\Logs',
    [switch]$RunNow
)

$ErrorActionPreference = 'Stop'
$Execute = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$BootstrapScript`""
$TaskNameForSchtasks = if ($TaskPath -and $TaskPath -ne '\') { ($TaskPath.TrimEnd('\') + '\' + $TaskName) } else { $TaskName }
$TaskRun = '"{0}" {1}' -f $Execute, $Arguments
$changed = $false

$cs = Get-CimInstance -ClassName Win32_ComputerSystem
if (-not $cs.PartOfDomain) {
    throw 'Endpoint must be domain joined before configuring the bootstrap task.'
}

$queryCommand = 'schtasks.exe /Query /TN "{0}" /XML 2>NUL' -f $TaskNameForSchtasks
$existingXml = & $env:ComSpec /c $queryCommand
$taskExists = $LASTEXITCODE -eq 0
$needsUpdate = $true
if ($taskExists) {
    $xmlText = $existingXml -join "`n"
    $needsUpdate = $xmlText -notmatch [regex]::Escape($BootstrapScript) -or
        $xmlText -notmatch '<UserId>S-1-5-18</UserId>' -or
        $xmlText -notmatch '<RunLevel>HighestAvailable</RunLevel>'
}

if ($needsUpdate) {
    & schtasks.exe /Create /TN $TaskNameForSchtasks /SC ONSTART /RU SYSTEM /RL HIGHEST /TR $TaskRun /F | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "schtasks /Create failed for $TaskNameForSchtasks with exit code $LASTEXITCODE."
    }
    $changed = $true
}

if ($RunNow) {
    & schtasks.exe /Run /TN $TaskNameForSchtasks | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "schtasks /Run failed for $TaskNameForSchtasks with exit code $LASTEXITCODE."
    }
    $changed = $true
    $deadline = (Get-Date).AddMinutes(20)
    do {
        Start-Sleep -Seconds 5
        $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction Stop
        $info = Get-ScheduledTaskInfo -TaskName $TaskName -ErrorAction Stop
    } while ($task.State -eq 'Running' -and (Get-Date) -lt $deadline)

    if ($task.State -eq 'Running') {
        throw "Timed out waiting for $TaskNameForSchtasks to finish."
    }
    if ($info.LastTaskResult -ne 0) {
        throw "Scheduled task $TaskNameForSchtasks failed with result $($info.LastTaskResult)."
    }
} else {
    $info = Get-ScheduledTaskInfo -TaskName $TaskName -ErrorAction Stop
}

$detections = @{
    NextcloudDesktop = Test-Path -LiteralPath 'C:\Program Files\Nextcloud\nextcloud.exe'
    NextcloudTalk = Test-Path -LiteralPath 'C:\Program Files\Nextcloud Talk\Nextcloud Talk.exe'
}

$logs = @()
if (Test-Path -LiteralPath $LogRoot) {
    $logs = @(Get-ChildItem -LiteralPath $LogRoot -Filter '*.log' -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 5 FullName, Length, LastWriteTime)
}

[pscustomobject]@{
    changed = $changed
    computerName = $env:COMPUTERNAME
    domain = $cs.Domain
    taskName = $TaskNameForSchtasks
    runCommand = $TaskRun
    runNow = [bool]$RunNow
    lastTaskResult = $info.LastTaskResult
    detections = $detections
    logs = $logs
} | ConvertTo-Json -Compress -Depth 4

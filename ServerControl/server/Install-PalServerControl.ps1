[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$PalServerRoot,
    [string]$ServerArguments = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run this installer from an elevated PowerShell window on the PalServer computer.'
}

$PalServerRoot = [System.IO.Path]::GetFullPath($PalServerRoot)
if ($PalServerRoot.StartsWith('\\')) { throw 'PalServerRoot must be the server-local path, not an SMB/UNC path.' }
$serverExe = Join-Path $PalServerRoot 'PalServer.exe'
$configPath = Join-Path $PalServerRoot 'Pal\Saved\Config\WindowsServer\PalWorldSettings.ini'
if (-not (Test-Path -LiteralPath $serverExe)) { throw "PalServer.exe not found under $PalServerRoot" }
if (-not (Test-Path -LiteralPath $configPath)) { throw "Active configuration not found: $configPath" }

$taskName = 'PalServer Control Agent'
$existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($null -ne $existingTask) {
    Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    $deadline = [DateTime]::UtcNow.AddSeconds(20)
    do {
        Start-Sleep -Milliseconds 250
        $existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    } while ($null -ne $existingTask -and $existingTask.State -eq 'Running' -and [DateTime]::UtcNow -lt $deadline)
    if ($null -ne $existingTask -and $existingTask.State -eq 'Running') {
        throw "The existing '$taskName' instance did not stop within 20 seconds."
    }
}

$installRoot = Join-Path $env:ProgramData 'PalServerControl'
$controlRoot = Join-Path $PalServerRoot 'ServerControl'
foreach ($directory in @($installRoot, $controlRoot, (Join-Path $controlRoot 'requests'), (Join-Path $controlRoot 'responses'), (Join-Path $controlRoot 'processing'))) {
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
}

$agentSource = Join-Path $PSScriptRoot 'PalServerControl-Agent.ps1'
$agentDestination = Join-Path $installRoot 'PalServerControl-Agent.ps1'
$settingsDestination = Join-Path $installRoot 'settings.json'
$startupSettingsPath = Join-Path $controlRoot 'startup-settings.json'
Copy-Item -LiteralPath $agentSource -Destination $agentDestination -Force
[ordered]@{ version = 1; palServerRoot = $PalServerRoot; serverArguments = $ServerArguments } | ConvertTo-Json | Set-Content -LiteralPath $settingsDestination -Encoding UTF8
if (-not (Test-Path -LiteralPath $startupSettingsPath)) {
    function Get-ArgumentValue {
        param([string]$Name, [string]$Default = '')
        $match = [regex]::Match($ServerArguments, "(?i)(?:^|\s)-$([regex]::Escape($Name))=([^\s]+)")
        if ($match.Success) { return $match.Groups[1].Value.Trim('"') }
        return $Default
    }
    function Has-ArgumentSwitch {
        param([string]$Name)
        return [regex]::IsMatch($ServerArguments, "(?i)(?:^|\s)-$([regex]::Escape($Name))(?=\s|$)")
    }
    $remainingArguments = $ServerArguments
    foreach ($valueName in @('port', 'players', 'publicip', 'publicport', 'logformat', 'NumberOfWorkerThreadsServer')) {
        $remainingArguments = [regex]::Replace($remainingArguments, "(?i)(^|\s)-$([regex]::Escape($valueName))=[^\s]+", ' ')
    }
    foreach ($switchName in @('publiclobby', 'enable-gamedata-api', 'useperfthreads', 'NoAsyncLoadingThread', 'UseMultithreadForDS')) {
        $remainingArguments = [regex]::Replace($remainingArguments, "(?i)(^|\s)-$([regex]::Escape($switchName))(?=\s|$)", ' ')
    }
    [ordered]@{
        version = 1
        port = [int](Get-ArgumentValue -Name 'port' -Default '8211')
        players = [int](Get-ArgumentValue -Name 'players' -Default '32')
        publiclobby = Has-ArgumentSwitch -Name 'publiclobby'
        publicip = Get-ArgumentValue -Name 'publicip'
        publicport = Get-ArgumentValue -Name 'publicport'
        logformat = (Get-ArgumentValue -Name 'logformat' -Default 'Text')
        enableGameDataApi = Has-ArgumentSwitch -Name 'enable-gamedata-api'
        useperfthreads = Has-ArgumentSwitch -Name 'useperfthreads'
        noAsyncLoadingThread = Has-ArgumentSwitch -Name 'NoAsyncLoadingThread'
        useMultithreadForDS = Has-ArgumentSwitch -Name 'UseMultithreadForDS'
        numberOfWorkerThreadsServer = Get-ArgumentValue -Name 'NumberOfWorkerThreadsServer'
        additionalArguments = $remainingArguments.Trim()
    } | ConvertTo-Json | Set-Content -LiteralPath $startupSettingsPath -Encoding UTF8
}

$content = [System.IO.File]::ReadAllText($configPath)
$matches = [regex]::Matches($content, '(?<![A-Za-z0-9_])RESTAPIEnabled=(True|False)')
if ($matches.Count -ne 1) { throw "Expected exactly one RESTAPIEnabled setting; found $($matches.Count)." }
if ($matches[0].Groups[1].Value -ne 'True') {
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    Copy-Item -LiteralPath $configPath -Destination "$configPath.backup-server-control-$timestamp"
    $content = [regex]::Replace($content, '(?<![A-Za-z0-9_])RESTAPIEnabled=(True|False)', 'RESTAPIEnabled=True')
    [System.IO.File]::WriteAllText($configPath, $content, [System.Text.UTF8Encoding]::new($false))
}

$quotedAgent = '"{0}"' -f $agentDestination
$quotedSettings = '"{0}"' -f $settingsDestination
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File $quotedAgent -SettingsPath $quotedSettings"
$trigger = New-ScheduledTaskTrigger -AtStartup
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -RestartCount 10 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit ([TimeSpan]::Zero)
$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force | Out-Null
Start-ScheduledTask -TaskName $taskName

Write-Host "Installed '$taskName'."
Write-Host "Control directory: $controlRoot"
Write-Host 'Restart PalServer once manually so RESTAPIEnabled=True takes effect.'

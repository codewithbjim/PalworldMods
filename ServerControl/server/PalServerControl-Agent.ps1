[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$SettingsPath,
    [switch]$Once
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Read-AgentSettings {
    if (-not (Test-Path -LiteralPath $SettingsPath)) {
        throw "Agent settings not found: $SettingsPath"
    }
    return Get-Content -LiteralPath $SettingsPath -Raw | ConvertFrom-Json
}

$agentSettings = Read-AgentSettings
$serverRoot = [string]$agentSettings.palServerRoot
$serverArguments = [string]$agentSettings.serverArguments
$controlRoot = Join-Path $serverRoot 'ServerControl'
$requestRoot = Join-Path $controlRoot 'requests'
$responseRoot = Join-Path $controlRoot 'responses'
$processingRoot = Join-Path $controlRoot 'processing'
$statusPath = Join-Path $controlRoot 'status.json'
$startupSettingsPath = Join-Path $controlRoot 'startup-settings.json'
$configPath = Join-Path $serverRoot 'Pal\Saved\Config\WindowsServer\PalWorldSettings.ini'
$serverExe = Join-Path $serverRoot 'PalServer.exe'

foreach ($directory in @($controlRoot, $requestRoot, $responseRoot, $processingRoot)) {
    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
}

# Remove incomplete files left by an interrupted or older helper version.
Get-ChildItem -LiteralPath $controlRoot -File -Filter 'status.json.tmp-*' -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
Get-ChildItem -LiteralPath $responseRoot -File -Filter '*.tmp-*' -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue

function Get-PalServerProcess {
    return @(Get-Process -Name 'PalServer' -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $serverExe })
}

function Write-JsonAtomic {
    param([Parameter(Mandatory)][object]$Value, [Parameter(Mandatory)][string]$Path)
    $temporaryPath = "$Path.tmp-$([guid]::NewGuid().ToString('N'))"
    $backupPath = $null
    try {
        $Value | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $temporaryPath -Encoding UTF8
        if (Test-Path -LiteralPath $Path) {
            $backupPath = "$Path.backup-$([guid]::NewGuid().ToString('N'))"
            [System.IO.File]::Replace($temporaryPath, $Path, $backupPath)
            Remove-Item -LiteralPath $backupPath -Force -ErrorAction SilentlyContinue
            $backupPath = $null
        }
        else {
            Move-Item -LiteralPath $temporaryPath -Destination $Path
        }
    }
    finally {
        Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
        if ($null -ne $backupPath) {
            Remove-Item -LiteralPath $backupPath -Force -ErrorAction SilentlyContinue
        }
    }
}

function Publish-Status {
    param(
        [AllowNull()][string]$Detail = $null,
        [ValidateSet('Starting', 'Stopping', 'Restarting')][string]$StateOverride
    )
    $processes = @(Get-PalServerProcess)
    $actualState = if ($processes.Count -gt 0) { 'Running' } else { 'Stopped' }
    $state = if ([string]::IsNullOrWhiteSpace($StateOverride)) { $actualState } else { $StateOverride }
    $currentPlayers = $null
    $maxPlayers = $null
    $uptimeSeconds = $null
    $serverFps = $null
    if ($actualState -eq 'Running') {
        try {
            $metrics = Invoke-PalApi -Method GET -Endpoint 'metrics' -Body $null
            if ($null -ne $metrics.PSObject.Properties['currentplayernum']) { $currentPlayers = $metrics.currentplayernum }
            if ($null -ne $metrics.PSObject.Properties['maxplayernum']) { $maxPlayers = $metrics.maxplayernum }
            if ($null -ne $metrics.PSObject.Properties['uptime']) { $uptimeSeconds = $metrics.uptime }
            if ($null -ne $metrics.PSObject.Properties['serverfps']) { $serverFps = $metrics.serverfps }
        }
        catch { }
    }
    if ($null -eq $Detail -and (Test-Path -LiteralPath $statusPath)) {
        try { $Detail = [string](Get-Content -LiteralPath $statusPath -Raw | ConvertFrom-Json).detail } catch { $Detail = '' }
    }
    if ($null -eq $Detail) { $Detail = '' }
    $status = [ordered]@{
        version = 1
        state = $state
        detail = $Detail
        processId = if ($processes.Count -gt 0) { $processes[0].Id } else { $null }
        currentPlayers = $currentPlayers
        maxPlayers = $maxPlayers
        uptimeSeconds = $uptimeSeconds
        serverFps = $serverFps
        updatedAtUtc = [DateTime]::UtcNow.ToString('o')
        agentMachine = $env:COMPUTERNAME
    }
    Write-JsonAtomic -Value $status -Path $statusPath
}

function Get-IniSetting {
    param([Parameter(Mandatory)][string]$Name)
    $content = [System.IO.File]::ReadAllText($configPath)
    $quoted = [regex]::Match($content, "(?<![A-Za-z0-9_])$([regex]::Escape($Name))=`"([^`"]*)`"")
    if ($quoted.Success) { return $quoted.Groups[1].Value }
    $plain = [regex]::Match($content, "(?<![A-Za-z0-9_])$([regex]::Escape($Name))=([^,)]*)")
    if ($plain.Success) { return $plain.Groups[1].Value }
    throw "Setting '$Name' was not found in PalWorldSettings.ini."
}

function Invoke-PalApi {
    param(
        [Parameter(Mandatory)][ValidateSet('GET', 'POST')][string]$Method,
        [Parameter(Mandatory)][string]$Endpoint,
        [object]$Body
    )
    $port = [int](Get-IniSetting -Name 'RESTAPIPort')
    $password = Get-IniSetting -Name 'AdminPassword'
    $basicBytes = [System.Text.Encoding]::UTF8.GetBytes("admin:$password")
    $headers = @{ Authorization = "Basic $([Convert]::ToBase64String($basicBytes))" }
    $parameters = @{
        Uri = "http://127.0.0.1:$port/v1/api/$Endpoint"
        Method = $Method
        Headers = $headers
        UseBasicParsing = $true
        TimeoutSec = 15
    }
    if ($null -ne $Body) {
        $parameters.ContentType = 'application/json'
        $parameters.Body = $Body | ConvertTo-Json -Compress
    }
    return Invoke-RestMethod @parameters
}

function Start-PalServer {
    param([ValidateSet('Starting', 'Restarting')][string]$TransitionState = 'Starting')
    if (@(Get-PalServerProcess).Count -gt 0) {
        return 'Server is already running.'
    }
    if (-not (Test-Path -LiteralPath $serverExe)) {
        throw "PalServer executable not found: $serverExe"
    }
    Publish-Status -StateOverride $TransitionState -Detail 'Starting the Palworld server.'
    $arguments = New-Object System.Collections.Generic.List[string]
    if (Test-Path -LiteralPath $startupSettingsPath) {
        $startup = Get-Content -LiteralPath $startupSettingsPath -Raw | ConvertFrom-Json
        if ([string]$startup.port) { $arguments.Add("-port=$($startup.port)") }
        if ([string]$startup.players) { $arguments.Add("-players=$($startup.players)") }
        if ([bool]$startup.publiclobby) { $arguments.Add('-publiclobby') }
        if ([string]$startup.publicip) { $arguments.Add("-publicip=$($startup.publicip)") }
        if ([string]$startup.publicport) { $arguments.Add("-publicport=$($startup.publicport)") }
        if ([string]$startup.logformat) { $arguments.Add("-logformat=$($startup.logformat.ToLowerInvariant())") }
        if ([bool]$startup.enableGameDataApi) { $arguments.Add('-enable-gamedata-api') }
        if ([bool]$startup.useperfthreads) { $arguments.Add('-useperfthreads') }
        if ([bool]$startup.noAsyncLoadingThread) { $arguments.Add('-NoAsyncLoadingThread') }
        if ([bool]$startup.useMultithreadForDS) { $arguments.Add('-UseMultithreadForDS') }
        if ([string]$startup.numberOfWorkerThreadsServer) { $arguments.Add("-NumberOfWorkerThreadsServer=$($startup.numberOfWorkerThreadsServer)") }
        if ([string]$startup.additionalArguments) { $arguments.Add([string]$startup.additionalArguments) }
    }
    elseif (-not [string]::IsNullOrWhiteSpace($serverArguments)) {
        $arguments.Add($serverArguments)
    }

    $startParameters = @{
        FilePath = $serverExe
        WorkingDirectory = $serverRoot
        PassThru = $true
    }
    if ($arguments.Count -gt 0) {
        $startParameters.ArgumentList = $arguments -join ' '
    }
    $process = Start-Process @startParameters
    Start-Sleep -Seconds 3
    if ($process.HasExited) {
        throw "PalServer exited immediately with code $($process.ExitCode)."
    }
    return "Server started with process ID $($process.Id)."
}

function Stop-PalServerGracefully {
    param([ValidateSet('Stopping', 'Restarting')][string]$TransitionState = 'Stopping')
    $processes = @(Get-PalServerProcess)
    if ($processes.Count -eq 0) {
        return 'Server is already stopped.'
    }

    $enabled = Get-IniSetting -Name 'RESTAPIEnabled'
    if ($enabled -ne 'True') {
        throw 'RESTAPIEnabled is not active. Restart PalServer once after installing the controller.'
    }

    $transitionDetail = if ($TransitionState -eq 'Restarting') { 'Restarting: waiting for graceful shutdown.' } else { 'Stopping: waiting for graceful shutdown.' }
    Publish-Status -StateOverride $TransitionState -Detail $transitionDetail

    $null = Invoke-PalApi -Method POST -Endpoint 'shutdown' -Body @{
        waittime = 10
        message = 'Server maintenance: graceful shutdown in 10 seconds.'
    }

    $deadline = [DateTime]::UtcNow.AddSeconds(75)
    while ([DateTime]::UtcNow -lt $deadline) {
        if (@(Get-PalServerProcess).Count -eq 0) {
            return 'Server shut down gracefully.'
        }
        Start-Sleep -Seconds 2
        Publish-Status -StateOverride $TransitionState -Detail $transitionDetail
    }
    throw 'PalServer did not exit within 75 seconds. It was not force-killed.'
}

function Invoke-ControlCommand {
    param([Parameter(Mandatory)][ValidateSet('start', 'stop', 'restart', 'status')][string]$Command)
    switch ($Command) {
        'start' { return Start-PalServer -TransitionState 'Starting' }
        'stop' { return Stop-PalServerGracefully -TransitionState 'Stopping' }
        'restart' {
            $stopResult = Stop-PalServerGracefully -TransitionState 'Restarting'
            Publish-Status -StateOverride 'Restarting' -Detail 'Restarting: shutdown complete; preparing to start.'
            Start-Sleep -Seconds 3
            $startResult = Start-PalServer -TransitionState 'Restarting'
            return "$stopResult $startResult"
        }
        'status' { return 'Status refreshed.' }
    }
}

function Process-Requests {
    $requests = @(Get-ChildItem -LiteralPath $requestRoot -Filter '*.json' -File -ErrorAction SilentlyContinue | Sort-Object CreationTimeUtc)
    foreach ($requestFile in $requests) {
        $processingPath = Join-Path $processingRoot $requestFile.Name
        try {
            Move-Item -LiteralPath $requestFile.FullName -Destination $processingPath -ErrorAction Stop
            $request = Get-Content -LiteralPath $processingPath -Raw | ConvertFrom-Json
            if ([string]$request.version -ne '1') { throw 'Unsupported request version.' }
            if ([string]$request.id -notmatch '^[a-f0-9]{32}$') { throw 'Invalid request ID.' }
            $command = [string]$request.command
            if ($command -notin @('start', 'stop', 'restart', 'status')) { throw 'Unsupported command.' }
            $detail = Invoke-ControlCommand -Command $command
            $response = [ordered]@{ version = 1; id = $request.id; command = $command; success = $true; detail = $detail; completedAtUtc = [DateTime]::UtcNow.ToString('o') }
            Write-JsonAtomic -Value $response -Path (Join-Path $responseRoot "$($request.id).json")
            Publish-Status -Detail $detail
        }
        catch {
            $requestId = [System.IO.Path]::GetFileNameWithoutExtension($requestFile.Name)
            $response = [ordered]@{ version = 1; id = $requestId; success = $false; detail = $_.Exception.Message; completedAtUtc = [DateTime]::UtcNow.ToString('o') }
            Write-JsonAtomic -Value $response -Path (Join-Path $responseRoot "$requestId.json")
            Publish-Status -Detail $_.Exception.Message
        }
        finally {
            if (Test-Path -LiteralPath $processingPath) { Remove-Item -LiteralPath $processingPath -Force }
        }
    }
}

do {
    try {
        Process-Requests
        Publish-Status
    }
    catch {
        try { Publish-Status -Detail "Agent error: $($_.Exception.Message)" } catch { }
    }
    if (-not $Once) { Start-Sleep -Seconds 2 }
} while (-not $Once)

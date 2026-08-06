[CmdletBinding()]
param(
    [ValidateRange(1024, 65535)]
    [int]$Port = 37429
)

$ErrorActionPreference = 'Stop'
$server = Join-Path $PSScriptRoot '..\App\Start-PalworldLiveMap.ps1'
$telemetry = Join-Path $PSScriptRoot 'fixture-telemetry.json'
$process = Start-Process powershell.exe -PassThru -WindowStyle Hidden -ArgumentList @(
    '-NoProfile',
    '-ExecutionPolicy', 'Bypass',
    '-File', $server,
    '-Port', $Port,
    '-NoBrowser',
    '-TelemetryPath', $telemetry
)

try {
    $response = $null
    for ($attempt = 0; $attempt -lt 30; $attempt++) {
        try {
            $response = Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:$Port/api/telemetry" -TimeoutSec 1
            break
        } catch {
            Start-Sleep -Milliseconds 100
        }
    }
    if ($null -eq $response) { throw 'Server did not start.' }
    $data = $response.Content | ConvertFrom-Json
    if ($data.status -ne 'fixture') { throw 'The telemetry response did not contain the fixture.' }

    $page = Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:$Port/" -TimeoutSec 2
    if ($page.Content -notmatch 'Palworld Live Map') { throw 'The map page was not served.' }

    $traversalStatus = 0
    try {
        Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:$Port/../README.md" -TimeoutSec 2 | Out-Null
        $traversalStatus = 200
    } catch {
        $traversalStatus = [int]$_.Exception.Response.StatusCode
    }
    if ($traversalStatus -ne 404) { throw "Traversal request returned $traversalStatus instead of 404." }
    Write-Host 'server tests passed'
} finally {
    if (-not $process.HasExited) { Stop-Process -Id $process.Id -Force }
}

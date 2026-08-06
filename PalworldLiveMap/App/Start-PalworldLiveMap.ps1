[CmdletBinding()]
param(
    [ValidateRange(1024, 65535)]
    [int]$Port = 37421,
    [switch]$NoBrowser,
    [string]$TelemetryPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$appRoot = [System.IO.Path]::GetFullPath($PSScriptRoot)
if (-not [string]::IsNullOrWhiteSpace($TelemetryPath)) {
    $TelemetryPath = [System.IO.Path]::GetFullPath($TelemetryPath)
}

$contentTypes = @{
    '.html' = 'text/html; charset=utf-8'
    '.js' = 'text/javascript; charset=utf-8'
    '.css' = 'text/css; charset=utf-8'
    '.json' = 'application/json; charset=utf-8'
    '.png' = 'image/png'
    '.webp' = 'image/webp'
    '.svg' = 'image/svg+xml'
    '.ico' = 'image/x-icon'
}

function Send-Response {
    param(
        [Parameter(Mandatory)] [System.IO.Stream]$Stream,
        [int]$StatusCode = 200,
        [string]$StatusText = 'OK',
        [string]$ContentType = 'text/plain; charset=utf-8',
        [byte[]]$Body = [byte[]]::new(0),
        [switch]$HeadOnly
    )

    $headers = "HTTP/1.1 $StatusCode $StatusText`r`n" +
        "Content-Type: $ContentType`r`n" +
        "Content-Length: $($Body.Length)`r`n" +
        "Cache-Control: no-store`r`n" +
        "X-Content-Type-Options: nosniff`r`n" +
        "Connection: close`r`n`r`n"
    $headerBytes = [System.Text.Encoding]::ASCII.GetBytes($headers)
    $Stream.Write($headerBytes, 0, $headerBytes.Length)
    if (-not $HeadOnly -and $Body.Length -gt 0) {
        $Stream.Write($Body, 0, $Body.Length)
    }
    $Stream.Flush()
}

function Get-TelemetryBytes {
    if ([string]::IsNullOrWhiteSpace($TelemetryPath) -or -not [System.IO.File]::Exists($TelemetryPath)) {
        return [System.Text.Encoding]::UTF8.GetBytes(
            '{"schemaVersion":1,"sequence":0,"connected":false,"status":"waiting-for-telemetry","world":"Palworld","position":{"x":null,"y":null,"z":null},"rotation":{"pitch":0,"yaw":0,"roll":0}}'
        )
    }
    for ($attempt = 0; $attempt -lt 3; $attempt++) {
        $stream = $null
        $memory = $null
        try {
            $stream = [System.IO.File]::Open(
                $TelemetryPath,
                [System.IO.FileMode]::Open,
                [System.IO.FileAccess]::Read,
                [System.IO.FileShare]::ReadWrite
            )
            try {
                $memory = [System.IO.MemoryStream]::new()
                $stream.CopyTo($memory)
                return $memory.ToArray()
            } finally {
                if ($null -ne $memory) { $memory.Dispose() }
                $stream.Dispose()
            }
        } catch {
            if ($attempt -eq 2) { throw }
        }
    }
}

$listener = [System.Net.Sockets.TcpListener]::new(
    [System.Net.IPAddress]::Loopback,
    $Port
)

try {
    $listener.Start()
    $url = "http://127.0.0.1:$Port/"
    Write-Host "Palworld Live Map is available at $url"
    if ([string]::IsNullOrWhiteSpace($TelemetryPath)) {
        Write-Host 'Telemetry: disconnected browser-test fixture'
    } else {
        Write-Host "Telemetry fixture: $TelemetryPath"
    }
    Write-Host 'Press Ctrl+C to stop.'
    if (-not $NoBrowser) {
        Start-Process $url
    }

    while ($true) {
        $client = $listener.AcceptTcpClient()
        $network = $null
        $reader = $null
        try {
            $client.ReceiveTimeout = 3000
            $network = $client.GetStream()
            $reader = [System.IO.StreamReader]::new(
                $network,
                [System.Text.Encoding]::ASCII,
                $false,
                1024,
                $true
            )
            $requestLine = $reader.ReadLine()
            while (($headerLine = $reader.ReadLine()) -ne $null -and $headerLine -ne '') {}

            if ($requestLine -notmatch '^(GET|HEAD)\s+([^\s]+)\s+HTTP/1\.[01]$') {
                Send-Response -Stream $network -StatusCode 400 -StatusText 'Bad Request'
                continue
            }

            $method = $Matches[1]
            $requestTarget = $Matches[2]
            $path = ([System.Uri]::new("http://localhost$requestTarget")).AbsolutePath
            if ($path -eq '/api/telemetry') {
                $body = Get-TelemetryBytes
                Send-Response -Stream $network -ContentType $contentTypes['.json'] -Body $body -HeadOnly:($method -eq 'HEAD')
                continue
            }

            if ($path -eq '/') { $path = '/index.html' }
            $relative = [System.Uri]::UnescapeDataString($path.TrimStart('/')).Replace('/', [System.IO.Path]::DirectorySeparatorChar)
            $candidate = [System.IO.Path]::GetFullPath((Join-Path $appRoot $relative))
            $safeRoot = $appRoot.TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
            if (-not $candidate.StartsWith($safeRoot, [System.StringComparison]::OrdinalIgnoreCase) -or -not [System.IO.File]::Exists($candidate)) {
                Send-Response -Stream $network -StatusCode 404 -StatusText 'Not Found'
                continue
            }

            $extension = [System.IO.Path]::GetExtension($candidate).ToLowerInvariant()
            $contentType = if ($contentTypes.ContainsKey($extension)) { $contentTypes[$extension] } else { 'application/octet-stream' }
            $body = [System.IO.File]::ReadAllBytes($candidate)
            Send-Response -Stream $network -ContentType $contentType -Body $body -HeadOnly:($method -eq 'HEAD')
        } catch {
            Write-Warning "Request failed: $($_.Exception.Message)"
        } finally {
            if ($null -ne $reader) { $reader.Dispose() }
            if ($null -ne $network) { $network.Dispose() }
            $client.Dispose()
        }
    }
} finally {
    $listener.Stop()
}

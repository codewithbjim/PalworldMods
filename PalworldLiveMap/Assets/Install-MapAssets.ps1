[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$SourceDirectory
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$sourceRoot = [System.IO.Path]::GetFullPath($SourceDirectory)
$destination = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\App\assets\maps'))
$required = @('T_WorldMap.webp', 'T_TreeMap.webp')

function Get-WebPDimensions {
    param([Parameter(Mandatory)][string]$Path)
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -lt 30 -or [System.Text.Encoding]::ASCII.GetString($bytes, 0, 4) -ne 'RIFF' -or [System.Text.Encoding]::ASCII.GetString($bytes, 8, 4) -ne 'WEBP') {
        throw "Not a supported WebP file: $Path"
    }
    $chunk = [System.Text.Encoding]::ASCII.GetString($bytes, 12, 4)
    if ($chunk -eq 'VP8X') {
        return @(1 + $bytes[24] + ($bytes[25] -shl 8) + ($bytes[26] -shl 16), 1 + $bytes[27] + ($bytes[28] -shl 8) + ($bytes[29] -shl 16))
    }
    if ($chunk -eq 'VP8 ') {
        return @(([System.BitConverter]::ToUInt16($bytes, 26) -band 0x3fff), ([System.BitConverter]::ToUInt16($bytes, 28) -band 0x3fff))
    }
    if ($chunk -eq 'VP8L') {
        return @(1 + $bytes[21] + (($bytes[22] -band 0x3f) -shl 8), 1 + ($bytes[22] -shr 6) + ($bytes[23] -shl 2) + (($bytes[24] -band 0x0f) -shl 10))
    }
    throw "Unsupported WebP encoding '$chunk': $Path"
}

if (-not [System.IO.Directory]::Exists($sourceRoot)) {
    throw "Map source directory does not exist: $sourceRoot"
}

[System.IO.Directory]::CreateDirectory($destination) | Out-Null
$manifest = [ordered]@{ schemaVersion = 1; installedAtUtc = [DateTime]::UtcNow.ToString('o'); assets = @() }

foreach ($name in $required) {
    $source = Join-Path $sourceRoot $name
    if (-not [System.IO.File]::Exists($source)) { throw "Required 8192x8192 map asset is missing: $source" }
    $dimensions = Get-WebPDimensions -Path $source
    if ($dimensions[0] -ne 8192 -or $dimensions[1] -ne 8192) {
        throw "Map asset must be 8192x8192, got $($dimensions[0])x$($dimensions[1]): $source"
    }
    $target = Join-Path $destination $name
    [System.IO.File]::Copy($source, $target, $true)
    $hash = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
    $manifest.assets += [pscustomobject][ordered]@{ name = $name; width = 8192; height = 8192; bytes = (Get-Item -LiteralPath $target).Length; sha256 = $hash }
}

$manifestPath = Join-Path $destination 'local-assets.json'
[System.IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 4), [System.Text.UTF8Encoding]::new($false))
$manifest.assets | Format-Table name, width, height, bytes, sha256 -AutoSize
Write-Host "Installed local-only map assets in $destination"

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$GameDataDirectory
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$gameDataRoot = [System.IO.Path]::GetFullPath($GameDataDirectory)
$charactersPath = Join-Path $gameDataRoot 'characters.json'
$sourceIcons = Join-Path $gameDataRoot 'icons\pals'
$destination = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\App\assets\pals'))
if (-not [System.IO.File]::Exists($charactersPath)) { throw "Characters data is missing: $charactersPath" }
if (-not [System.IO.Directory]::Exists($sourceIcons)) { throw "Pal icon directory is missing: $sourceIcons" }

[System.IO.Directory]::CreateDirectory($destination) | Out-Null
$data = Get-Content -LiteralPath $charactersPath -Raw | ConvertFrom-Json
$seen = @{}
$catalog = @()
$assets = @()
foreach ($pal in $data.pals) {
    if ([string]::IsNullOrWhiteSpace($pal.name) -or $pal.name -match '\(Boss\)$' -or $seen.ContainsKey($pal.name)) { continue }
    $filename = [System.IO.Path]::GetFileName([string]$pal.icon)
    $source = Join-Path $sourceIcons $filename
    if (-not [System.IO.File]::Exists($source)) { continue }
    $seen[$pal.name] = $true
    $target = Join-Path $destination $filename
    [System.IO.File]::Copy($source, $target, $true)
    $id = 'pal-' + ([string]$pal.asset).ToLowerInvariant().Replace('_', '-')
    $catalog += [pscustomobject][ordered]@{ id = $id; label = [string]$pal.name; image = "assets/pals/$filename" }
    $assets += [pscustomobject][ordered]@{ name = $filename; bytes = (Get-Item -LiteralPath $target).Length; sha256 = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash }
}

$catalog = @($catalog | Sort-Object label)
$json = $catalog | ConvertTo-Json -Depth 3 -Compress
[System.IO.File]::WriteAllText((Join-Path $destination 'pal-catalog.js'), "window.PalLocationCatalog = Object.freeze($json);", [System.Text.UTF8Encoding]::new($false))
$manifest = [ordered]@{ schemaVersion = 1; installedAtUtc = [DateTime]::UtcNow.ToString('o'); count = $catalog.Count; assets = $assets }
[System.IO.File]::WriteAllText((Join-Path $destination 'local-assets.json'), ($manifest | ConvertTo-Json -Depth 4), [System.Text.UTF8Encoding]::new($false))
Write-Host "Installed $($catalog.Count) local Pal filters and portraits in $destination"

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Destination,

    [string]$ThumbnailSource
)

$ErrorActionPreference = "Stop"
$releaseRoot = $PSScriptRoot
$repoRoot = Split-Path -Parent $releaseRoot
$modRoot = Join-Path $repoRoot "PerfectPlacement"
$pakSource = Join-Path $repoRoot "PerfectPlacementBlueprint\PalworldModdingKit\Saved\StagedBuilds\Windows\Pal\Content\Paks\pakchunk1-Windows.pak"
$destinationRoot = [System.IO.Path]::GetFullPath($Destination)

foreach ($required in @(
    (Join-Path $modRoot "Info.json"),
    (Join-Path $modRoot "Scripts\main.lua"),
    (Join-Path $modRoot "Scripts\config.lua"),
    $pakSource
)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Required Workshop package input not found: $required"
    }
}

New-Item -ItemType Directory -Force -Path $destinationRoot | Out-Null
$scriptsDestination = Join-Path $destinationRoot "Scripts"
$logicModsDestination = Join-Path $destinationRoot "LogicMods"
New-Item -ItemType Directory -Force -Path $scriptsDestination, $logicModsDestination | Out-Null

Copy-Item -LiteralPath (Join-Path $modRoot "Info.json") -Destination $destinationRoot -Force
Copy-Item -LiteralPath (Join-Path $modRoot "Scripts\main.lua") -Destination $scriptsDestination -Force
Copy-Item -LiteralPath (Join-Path $modRoot "Scripts\config.lua") -Destination $scriptsDestination -Force
Copy-Item -LiteralPath $pakSource -Destination (Join-Path $logicModsDestination "PerfectPlacement.pak") -Force

$thumbnailDestination = Join-Path $destinationRoot "thumbnail.png"
if ($ThumbnailSource) {
    $resolvedThumbnailSource = [System.IO.Path]::GetFullPath($ThumbnailSource)
    if (-not (Test-Path -LiteralPath $resolvedThumbnailSource -PathType Leaf)) {
        throw "Thumbnail source not found: $resolvedThumbnailSource"
    }
    if ((Get-Item -LiteralPath $resolvedThumbnailSource).Length -ge 1MB) {
        throw "Thumbnail must be smaller than Steam's 1 MB limit: $resolvedThumbnailSource"
    }
    Copy-Item -LiteralPath $resolvedThumbnailSource -Destination $thumbnailDestination -Force
} elseif (-not (Test-Path -LiteralPath $thumbnailDestination -PathType Leaf)) {
    throw "The destination has no thumbnail.png. Supply -ThumbnailSource with a file smaller than 1 MB."
}

$manifest = Get-Content -LiteralPath (Join-Path $destinationRoot "Info.json") -Raw | ConvertFrom-Json
if ($manifest.PackageName -ne "PerfectPlacement") {
    throw "Unexpected PackageName in staged Info.json: $($manifest.PackageName)"
}
if (-not ($manifest.Dependencies -contains "UE4SS")) {
    throw "The staged package does not declare its UE4SS dependency."
}
foreach ($type in @("Lua", "LogicMods")) {
    if (-not ($manifest.InstallRule.Type -contains $type)) {
        throw "The staged package is missing the $type InstallRule."
    }
}

Write-Host "Staged Workshop package at $destinationRoot"

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Destination,

    [string]$ThumbnailSource,

    [string]$Version = "0.2.0-rc.5"
)

$ErrorActionPreference = "Stop"
$releaseRoot = $PSScriptRoot
$repoRoot = Split-Path -Parent $releaseRoot
$modRoot = Join-Path $repoRoot "PerfectPlacement"
$pakSource = Join-Path $releaseRoot "Assets\PerfectPlacement.pak"
$pakHashPath = Join-Path $releaseRoot "Assets\PerfectPlacement.pak.sha256"
$destinationRoot = [System.IO.Path]::GetFullPath($Destination)
if (-not $ThumbnailSource) {
    $ThumbnailSource = Join-Path $releaseRoot "thumbnail.png"
}

foreach ($required in @(
    (Join-Path $modRoot "Info.json"),
    (Join-Path $modRoot "Scripts\main.lua"),
    (Join-Path $modRoot "Scripts\config.lua"),
    (Join-Path $modRoot "Scripts\gamepad.lua"),
    (Join-Path $modRoot "Scripts\keybindings.lua"),
    (Join-Path $modRoot "Scripts\runtime.lua"),
    (Join-Path $modRoot "Scripts\darnmenu.lua"),
    $pakSource,
    $pakHashPath
)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Required Workshop package input not found: $required"
    }
}

$expectedPakHash = (
    (Get-Content -LiteralPath $pakHashPath -Raw).Trim() -split "\s+"
)[0].ToUpperInvariant()
$actualPakHash = (Get-FileHash -LiteralPath $pakSource -Algorithm SHA256).Hash
if ($actualPakHash -ne $expectedPakHash) {
    throw "Workshop PAK hash '$actualPakHash' does not match '$expectedPakHash'."
}

New-Item -ItemType Directory -Force -Path $destinationRoot | Out-Null
$scriptsDestination = Join-Path $destinationRoot "Scripts"
$logicModsDestination = Join-Path $destinationRoot "LogicMods"
foreach ($payloadDirectory in @($scriptsDestination, $logicModsDestination)) {
    if (Test-Path -LiteralPath $payloadDirectory) {
        Remove-Item -LiteralPath $payloadDirectory -Recurse -Force
    }
}
foreach ($legacyPayload in @(
    (Join-Path $destinationRoot "PerfectPlacement.modconfig.json")
)) {
    if (Test-Path -LiteralPath $legacyPayload) {
        Remove-Item -LiteralPath $legacyPayload -Force
    }
}
New-Item -ItemType Directory -Force -Path $scriptsDestination, $logicModsDestination | Out-Null

Copy-Item -LiteralPath (Join-Path $modRoot "Info.json") -Destination $destinationRoot -Force
foreach ($scriptName in @(
    "main.lua",
    "config.lua",
    "gamepad.lua",
    "keybindings.lua",
    "runtime.lua",
    "darnmenu.lua"
)) {
    Copy-Item -LiteralPath (Join-Path $modRoot "Scripts\$scriptName") -Destination $scriptsDestination -Force
}
Copy-Item -LiteralPath $pakSource -Destination (Join-Path $logicModsDestination "PerfectPlacement.pak") -Force

$thumbnailDestination = Join-Path $destinationRoot "thumbnail.png"
$resolvedThumbnailSource = [System.IO.Path]::GetFullPath($ThumbnailSource)
if (-not (Test-Path -LiteralPath $resolvedThumbnailSource -PathType Leaf)) {
    throw "Thumbnail source not found: $resolvedThumbnailSource"
}
if ((Get-Item -LiteralPath $resolvedThumbnailSource).Length -ge 1MB) {
    throw "Thumbnail must be smaller than Steam's 1 MB limit: $resolvedThumbnailSource"
}
Copy-Item -LiteralPath $resolvedThumbnailSource -Destination $thumbnailDestination -Force

$manifest = Get-Content -LiteralPath (Join-Path $destinationRoot "Info.json") -Raw | ConvertFrom-Json
if ($manifest.PackageName -ne "PerfectPlacement") {
    throw "Unexpected PackageName in staged Info.json: $($manifest.PackageName)"
}
if ($manifest.Version -ne $Version) {
    throw "Staged version '$($manifest.Version)' does not match '$Version'."
}
if ($manifest.Thumbnail -ne "thumbnail.png") {
    throw "Info.json Thumbnail must be 'thumbnail.png' to match the staged Workshop asset."
}
if (-not ($manifest.Dependencies -contains "UE4SSExperimentalPW")) {
    throw "The staged package does not declare the official UE4SS Experimental package dependency."
}
if ($manifest.Dependencies -contains "DarnMenu") {
    throw "DarnMenu must remain an optional integration, not a hard package dependency."
}
if (@($manifest.Dependencies).Count -ne 1) {
    throw "The staged package must contain only the UE4SSExperimentalPW hard dependency."
}
foreach ($type in @("Lua", "LogicMods")) {
    if (-not ($manifest.InstallRule.Type -contains $type)) {
        throw "The staged package is missing the $type InstallRule."
    }
}
$logicModsRule = $manifest.InstallRule | Where-Object Type -eq "LogicMods"
if ($logicModsRule.Targets.Count -ne 1 -or $logicModsRule.Targets[0] -ne "./LogicMods/PerfectPlacement.pak") {
    throw "The LogicMods InstallRule must target the PAK file directly to avoid a nested LogicMods directory."
}

Write-Host "Staged Perfect Placement $Version Workshop package at $destinationRoot"

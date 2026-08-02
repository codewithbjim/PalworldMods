[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Destination,

    [string]$ThumbnailSource,

    [string]$Version = "0.3.0-alpha.2"
)

$ErrorActionPreference = "Stop"
$releaseRoot = $PSScriptRoot
$repoRoot = Split-Path -Parent $releaseRoot
$modRoot = Join-Path $repoRoot "PerfectPlacement"
$nativePakSource = Join-Path $releaseRoot "Assets\PerfectPlacement_NativeUI_P.pak"
$nativePakHashPath = Join-Path $releaseRoot "Assets\PerfectPlacement_NativeUI_P.pak.sha256"
$destinationRoot = [System.IO.Path]::GetFullPath($Destination)
if (-not $ThumbnailSource) {
    $ThumbnailSource = Join-Path $releaseRoot "thumbnail.png"
}

foreach ($required in @(
    (Join-Path $modRoot "Info.json"),
    (Join-Path $modRoot "Scripts\main.lua"),
    (Join-Path $modRoot "Scripts\config.lua"),
    (Join-Path $modRoot "Scripts\gamepad.lua"),
    (Join-Path $modRoot "Scripts\companion_bridge.lua"),
    (Join-Path $modRoot "Scripts\keybindings.lua"),
    (Join-Path $modRoot "Scripts\runtime.lua"),
    (Join-Path $modRoot "Scripts\darnmenu.lua"),
    $nativePakSource,
    $nativePakHashPath
)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Required Workshop package input not found: $required"
    }
}

$expectedNativePakHash = (
    (Get-Content -LiteralPath $nativePakHashPath -Raw).Trim() -split "\s+"
)[0].ToUpperInvariant()
$actualNativePakHash = (
    Get-FileHash -LiteralPath $nativePakSource -Algorithm SHA256
).Hash
if ($actualNativePakHash -ne $expectedNativePakHash) {
    throw "Workshop native UI PAK hash '$actualNativePakHash' does not match '$expectedNativePakHash'."
}

New-Item -ItemType Directory -Force -Path $destinationRoot | Out-Null
$scriptsDestination = Join-Path $destinationRoot "Scripts"
$paksDestination = Join-Path $destinationRoot "Paks"
foreach ($payloadDirectory in @($scriptsDestination, $paksDestination)) {
    if (Test-Path -LiteralPath $payloadDirectory) {
        Remove-Item -LiteralPath $payloadDirectory -Recurse -Force
    }
}
foreach ($legacyPayload in @(
    (Join-Path $destinationRoot "PerfectPlacement.modconfig.json"),
    (Join-Path $destinationRoot "LogicMods")
)) {
    if (Test-Path -LiteralPath $legacyPayload) {
        Remove-Item -LiteralPath $legacyPayload -Recurse -Force
    }
}
New-Item -ItemType Directory -Force -Path $scriptsDestination, $paksDestination | Out-Null

Copy-Item -LiteralPath (Join-Path $modRoot "Info.json") -Destination $destinationRoot -Force
foreach ($scriptName in @(
    "main.lua",
    "config.lua",
    "gamepad.lua",
    "companion_bridge.lua",
    "keybindings.lua",
    "runtime.lua",
    "darnmenu.lua"
)) {
    Copy-Item -LiteralPath (Join-Path $modRoot "Scripts\$scriptName") -Destination $scriptsDestination -Force
}
Copy-Item -LiteralPath $nativePakSource -Destination (Join-Path $paksDestination "PerfectPlacement_NativeUI_P.pak") -Force

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
foreach ($type in @("Lua", "Paks")) {
    if (-not ($manifest.InstallRule.Type -contains $type)) {
        throw "The staged package is missing the $type InstallRule."
    }
}
$paksRule = $manifest.InstallRule | Where-Object Type -eq "Paks"
if ($paksRule.Targets.Count -ne 1 -or $paksRule.Targets[0] -ne "./Paks/PerfectPlacement_NativeUI_P.pak") {
    throw "The Paks InstallRule must target the native UI PAK file directly."
}
if ($manifest.InstallRule.Type -contains "LogicMods") {
    throw "The consolidated package must not contain a LogicMods InstallRule."
}

Write-Host "Staged Perfect Placement $Version Workshop package at $destinationRoot"

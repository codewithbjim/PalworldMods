[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Destination,
    [string]$Version = "0.1.1-hotfix.1"
)

$ErrorActionPreference = "Stop"
$releaseRoot = $PSScriptRoot
$repoRoot = Split-Path -Parent (Split-Path -Parent $releaseRoot)
$modRoot = Join-Path $repoRoot "QuickConnectManager"
$pakSource = Join-Path $releaseRoot "Assets\QuickConnectManager_UI_P.pak"
$pakHashPath = Join-Path $releaseRoot "Assets\QuickConnectManager_UI_P.pak.sha256"
$thumbnailSource = Join-Path $releaseRoot "thumbnail.png"
$destinationRoot = [System.IO.Path]::GetFullPath($Destination)
$scriptNames = @("config.lua", "discovery.lua", "launch_ui.lua", "main.lua", "servers.lua")

if ([System.IO.Path]::GetPathRoot($destinationRoot) -eq $destinationRoot) {
    throw "Workshop destination cannot be a drive root."
}
foreach ($required in @(
    (Join-Path $modRoot "Info.json"),
    $pakSource,
    $pakHashPath,
    $thumbnailSource
)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Required Workshop package input not found: $required"
    }
}
foreach ($scriptName in $scriptNames) {
    $required = Join-Path $modRoot "Scripts\$scriptName"
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Required runtime script not found: $required"
    }
}

$expectedPakHash = ((Get-Content -LiteralPath $pakHashPath -Raw).Trim() -split "\s+")[0].ToUpperInvariant()
$actualPakHash = (Get-FileHash -LiteralPath $pakSource -Algorithm SHA256).Hash
if ($actualPakHash -ne $expectedPakHash) {
    throw "Workshop PAK hash '$actualPakHash' does not match '$expectedPakHash'."
}
if ((Get-Item -LiteralPath $thumbnailSource).Length -ge 1MB) {
    throw "Thumbnail must be smaller than Steam's 1 MB limit."
}

New-Item -ItemType Directory -Force -Path $destinationRoot | Out-Null
$scriptsDestination = Join-Path $destinationRoot "Scripts"
$paksDestination = Join-Path $destinationRoot "Paks"
foreach ($payloadDirectory in @($scriptsDestination, $paksDestination)) {
    if (Test-Path -LiteralPath $payloadDirectory) {
        Remove-Item -LiteralPath $payloadDirectory -Recurse -Force
    }
}
New-Item -ItemType Directory -Force -Path $scriptsDestination, $paksDestination | Out-Null

Copy-Item -LiteralPath (Join-Path $modRoot "Info.json") -Destination $destinationRoot -Force
Copy-Item -LiteralPath $thumbnailSource -Destination (Join-Path $destinationRoot "thumbnail.png") -Force
foreach ($scriptName in $scriptNames) {
    Copy-Item -LiteralPath (Join-Path $modRoot "Scripts\$scriptName") -Destination (Join-Path $scriptsDestination $scriptName) -Force
}
Copy-Item -LiteralPath $pakSource -Destination (Join-Path $paksDestination "QuickConnectManager_UI_P.pak") -Force

$manifest = Get-Content -LiteralPath (Join-Path $destinationRoot "Info.json") -Raw -Encoding UTF8 | ConvertFrom-Json
if ($manifest.PackageName -ne "QuickConnectManager" -or $manifest.Version -ne $Version) {
    throw "Staged Workshop manifest identity or version is invalid."
}
if ($manifest.Thumbnail -ne "thumbnail.png") {
    throw "Staged Workshop manifest must reference thumbnail.png."
}
if (@($manifest.Dependencies).Count -ne 1 -or $manifest.Dependencies[0] -ne "UE4SSExperimentalPW") {
    throw "Staged Workshop manifest dependency is invalid."
}
$luaRule = @($manifest.InstallRule | Where-Object Type -eq "Lua")
$pakRule = @($manifest.InstallRule | Where-Object Type -eq "Paks")
if ($luaRule.Count -ne 1 -or $luaRule[0].Targets[0] -ne "./Scripts") {
    throw "Staged Workshop Lua InstallRule is invalid."
}
if ($pakRule.Count -ne 1 -or $pakRule[0].Targets.Count -ne 1 -or $pakRule[0].Targets[0] -ne "./Paks/") {
    throw "Staged Workshop Paks InstallRule is invalid."
}
Write-Host "Staged Quick Connect Manager $Version Workshop package at $destinationRoot"

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$GameRoot
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$sourcePak = Join-Path $PSScriptRoot 'PalworldModdingKit\Saved\StagedBuilds\Windows\Pal\Content\Paks\pakchunk1-Windows.pak'
$sourceMod = Join-Path $repoRoot 'PerfectPlacement'
$resolvedGameRoot = [System.IO.Path]::GetFullPath($GameRoot)
$destinationPak = Join-Path $resolvedGameRoot 'Pal\Content\Paks\LogicMods\PerfectPlacement.pak'
$destinationMod = Join-Path $resolvedGameRoot 'Pal\Binaries\Win64\ue4ss\Mods\PerfectPlacement'
$runtimeFiles = @(
    'enabled.txt'
    'Info.json'
    'Scripts\main.lua'
    'Scripts\config.lua'
    'Scripts\keybindings.lua'
    'Scripts\darnmenu.lua'
)

if (Get-Process -Name 'Palworld-Win64-Shipping' -ErrorAction SilentlyContinue) {
    throw 'Palworld is running. Close the game before deploying Perfect Placement.'
}

if (-not (Test-Path -LiteralPath (Join-Path $resolvedGameRoot 'Pal') -PathType Container)) {
    throw "Palworld content directory was not found under: $resolvedGameRoot"
}

if (-not (Test-Path -LiteralPath $sourcePak -PathType Leaf)) {
    throw "Packaged pak was not found: $sourcePak"
}

foreach ($relativePath in $runtimeFiles) {
    $sourcePath = Join-Path $sourceMod $relativePath
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
        throw "Runtime mod file was not found: $sourcePath"
    }
}

New-Item -ItemType Directory -Path (Split-Path -Parent $destinationPak), $destinationMod -Force | Out-Null
Copy-Item -LiteralPath $sourcePak -Destination $destinationPak -Force

$sourceHash = (Get-FileHash -LiteralPath $sourcePak -Algorithm SHA256).Hash
$destinationHash = (Get-FileHash -LiteralPath $destinationPak -Algorithm SHA256).Hash

if ($sourceHash -ne $destinationHash) {
    throw 'Pak deployment verification failed: source and destination hashes do not match.'
}

foreach ($relativePath in $runtimeFiles) {
    $sourcePath = Join-Path $sourceMod $relativePath
    $destinationPath = Join-Path $destinationMod $relativePath
    $destinationDirectory = Split-Path -Parent $destinationPath

    New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
    Copy-Item -LiteralPath $sourcePath -Destination $destinationPath -Force

    $sourceHash = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash
    $destinationHash = (Get-FileHash -LiteralPath $destinationPath -Algorithm SHA256).Hash

    if ($sourceHash -ne $destinationHash) {
        throw "Runtime deployment verification failed for: $relativePath"
    }
}

Write-Host 'Deployed and verified Perfect Placement:' -ForegroundColor Green
Write-Host "  Pak: $destinationPak"
Write-Host "  UE4SS mod: $destinationMod"

[CmdletBinding()]
param(
    [string]$Version = "0.1.0",
    [switch]$KeepStage
)

$ErrorActionPreference = "Stop"
$releaseRoot = $PSScriptRoot
$repoRoot = Split-Path -Parent $releaseRoot
$stageRoot = Join-Path $releaseRoot "Stage"
$distRoot = Join-Path $releaseRoot "Dist"
$zipPath = Join-Path $distRoot "PerfectPlacement-$Version.zip"
$luaSource = Join-Path $repoRoot "PerfectPlacement"
$pakSource = Join-Path $repoRoot "PerfectPlacementBlueprint\PalworldModdingKit\Saved\StagedBuilds\Windows\Pal\Content\Paks\PerfectPlacement.pak"
$luaDestination = Join-Path $stageRoot "Pal\Binaries\Win64\UE4SS\Mods\PerfectPlacement"
$pakDestination = Join-Path $stageRoot "Pal\Content\Paks\LogicMods"

foreach ($required in @(
    (Join-Path $luaSource "Info.json"),
    (Join-Path $luaSource "enabled.txt"),
    (Join-Path $luaSource "Scripts\main.lua"),
    (Join-Path $luaSource "Scripts\config.lua"),
    $pakSource,
    (Join-Path $releaseRoot "README.txt"),
    (Join-Path $releaseRoot "CHANGELOG.md")
)) {
    if (-not (Test-Path -LiteralPath $required)) {
        throw "Required release input not found: $required"
    }
}

$manifest = Get-Content -LiteralPath (Join-Path $luaSource "Info.json") -Raw | ConvertFrom-Json
if ($manifest.Version -ne $Version) {
    throw "Info.json version '$($manifest.Version)' does not match requested version '$Version'."
}

if (Test-Path -LiteralPath $stageRoot) {
    Remove-Item -LiteralPath $stageRoot -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $luaDestination, $pakDestination, $distRoot | Out-Null

Copy-Item -LiteralPath (Join-Path $luaSource "enabled.txt") -Destination $luaDestination
Copy-Item -LiteralPath (Join-Path $luaSource "Info.json") -Destination $luaDestination
Copy-Item -LiteralPath (Join-Path $luaSource "README.md") -Destination $luaDestination
Copy-Item -LiteralPath (Join-Path $luaSource "Scripts") -Destination $luaDestination -Recurse
Copy-Item -LiteralPath $pakSource -Destination (Join-Path $pakDestination "PerfectPlacement.pak")
Copy-Item -LiteralPath (Join-Path $releaseRoot "README.txt") -Destination $stageRoot
Copy-Item -LiteralPath (Join-Path $releaseRoot "CHANGELOG.md") -Destination $stageRoot

if (Test-Path -LiteralPath $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force
}
Compress-Archive -Path (Join-Path $stageRoot "*") -DestinationPath $zipPath -CompressionLevel Optimal

$zip = Get-Item -LiteralPath $zipPath
Write-Host "Built $($zip.FullName) ($($zip.Length) bytes)"

if (-not $KeepStage) {
    Remove-Item -LiteralPath $stageRoot -Recurse -Force
}

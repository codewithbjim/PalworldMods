[CmdletBinding()]
param(
    [string]$Version = "0.2.0-beta.2",
    [switch]$KeepStage
)

$ErrorActionPreference = "Stop"
$releaseRoot = $PSScriptRoot
$repoRoot = Split-Path -Parent $releaseRoot
$stageRoot = Join-Path $releaseRoot "Stage"
$distRoot = Join-Path $releaseRoot "Dist"
$zipPath = Join-Path $distRoot "PerfectPlacement-$Version.zip"
$luaSource = Join-Path $repoRoot "PerfectPlacement"
$pakSource = Join-Path $repoRoot "PerfectPlacementBlueprint\PalworldModdingKit\Saved\StagedBuilds\Windows\Pal\Content\Paks\pakchunk1-Windows.pak"
$thumbnailSource = Join-Path $releaseRoot "thumbnail.png"
$luaDestination = Join-Path $stageRoot "Pal\Binaries\Win64\UE4SS\Mods\PerfectPlacement"
$pakDestination = Join-Path $stageRoot "Pal\Content\Paks\LogicMods"

foreach ($required in @(
    (Join-Path $luaSource "Info.json"),
    (Join-Path $luaSource "enabled.txt"),
    (Join-Path $luaSource "Scripts\main.lua"),
    (Join-Path $luaSource "Scripts\config.lua"),
    (Join-Path $luaSource "Scripts\keybindings.lua"),
    (Join-Path $luaSource "Scripts\darnmenu.lua"),
    $pakSource,
    $thumbnailSource,
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
if ($manifest.Thumbnail -ne "thumbnail.png") {
    throw "Info.json Thumbnail must be 'thumbnail.png' to match the packaged release asset."
}
if ((Get-Item -LiteralPath $thumbnailSource).Length -ge 1MB) {
    throw "Thumbnail must be smaller than Steam's 1 MB limit: $thumbnailSource"
}

if (Test-Path -LiteralPath $stageRoot) {
    Remove-Item -LiteralPath $stageRoot -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $luaDestination, $pakDestination, $distRoot | Out-Null

Copy-Item -LiteralPath (Join-Path $luaSource "enabled.txt") -Destination $luaDestination
Copy-Item -LiteralPath (Join-Path $luaSource "Info.json") -Destination $luaDestination
Copy-Item -LiteralPath $thumbnailSource -Destination (Join-Path $luaDestination "thumbnail.png")
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

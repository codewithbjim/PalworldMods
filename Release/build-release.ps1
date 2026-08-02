[CmdletBinding()]
param(
    [string]$Version = "0.3.0-alpha.1",
    [switch]$KeepStage
)

$ErrorActionPreference = "Stop"
$releaseRoot = $PSScriptRoot
$repoRoot = Split-Path -Parent $releaseRoot
$stageRoot = Join-Path $releaseRoot "Stage"
$distRoot = Join-Path $releaseRoot "Dist"
$zipPath = Join-Path $distRoot "PerfectPlacement-$Version.zip"
$luaSource = Join-Path $repoRoot "PerfectPlacement"
$nativePakSource = Join-Path $releaseRoot "Assets\PerfectPlacement_NativeUI_P.pak"
$nativePakHashPath = Join-Path $releaseRoot "Assets\PerfectPlacement_NativeUI_P.pak.sha256"
$thumbnailSource = Join-Path $releaseRoot "thumbnail.png"
$luaDestination = Join-Path $stageRoot "Pal\Binaries\Win64\UE4SS\Mods\PerfectPlacement"
$nativePakDestination = Join-Path $stageRoot "Pal\Content\Paks\~mods"

foreach ($required in @(
    (Join-Path $luaSource "Info.json"),
    (Join-Path $luaSource "enabled.txt"),
    (Join-Path $luaSource "Scripts\main.lua"),
    (Join-Path $luaSource "Scripts\config.lua"),
    (Join-Path $luaSource "Scripts\gamepad.lua"),
    (Join-Path $luaSource "Scripts\companion_bridge.lua"),
    (Join-Path $luaSource "Scripts\keybindings.lua"),
    (Join-Path $luaSource "Scripts\runtime.lua"),
    (Join-Path $luaSource "Scripts\darnmenu.lua"),
    $nativePakSource,
    $nativePakHashPath,
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
if (-not ($manifest.Dependencies -contains "UE4SSExperimentalPW")) {
    throw "Info.json must declare the official UE4SS Experimental package dependency."
}
if ($manifest.Dependencies -contains "DarnMenu") {
    throw "DarnMenu must remain an optional integration, not a hard package dependency."
}
if (@($manifest.Dependencies).Count -ne 1) {
    throw "Info.json must contain only the UE4SSExperimentalPW hard dependency."
}
if ($manifest.Thumbnail -ne "thumbnail.png") {
    throw "Info.json Thumbnail must be 'thumbnail.png' to match the packaged release asset."
}
if ((Get-Item -LiteralPath $thumbnailSource).Length -ge 1MB) {
    throw "Thumbnail must be smaller than Steam's 1 MB limit: $thumbnailSource"
}
$expectedNativePakHash = (
    (Get-Content -LiteralPath $nativePakHashPath -Raw).Trim() -split "\s+"
)[0].ToUpperInvariant()
$actualNativePakHash = (
    Get-FileHash -LiteralPath $nativePakSource -Algorithm SHA256
).Hash
if ($actualNativePakHash -ne $expectedNativePakHash) {
    throw "Native UI PAK hash '$actualNativePakHash' does not match '$expectedNativePakHash'."
}

if (Test-Path -LiteralPath $stageRoot) {
    Remove-Item -LiteralPath $stageRoot -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $luaDestination, $nativePakDestination, $distRoot | Out-Null

Copy-Item -LiteralPath (Join-Path $luaSource "enabled.txt") -Destination $luaDestination
Copy-Item -LiteralPath (Join-Path $luaSource "Info.json") -Destination $luaDestination
Copy-Item -LiteralPath $thumbnailSource -Destination (Join-Path $luaDestination "thumbnail.png")
Copy-Item -LiteralPath (Join-Path $luaSource "README.md") -Destination $luaDestination
Copy-Item -LiteralPath (Join-Path $luaSource "Scripts") -Destination $luaDestination -Recurse
Copy-Item -LiteralPath $nativePakSource -Destination (Join-Path $nativePakDestination "PerfectPlacement_NativeUI_P.pak")
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

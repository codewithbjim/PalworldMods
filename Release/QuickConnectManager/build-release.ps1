[CmdletBinding()]
param(
    [string]$Version = "0.2.0-hotfix.1",
    [switch]$KeepStage
)

$ErrorActionPreference = "Stop"
$releaseRoot = $PSScriptRoot
$repoRoot = Split-Path -Parent (Split-Path -Parent $releaseRoot)
$modRoot = Join-Path $repoRoot "QuickConnectManager"
$stageRoot = Join-Path $releaseRoot "Stage"
$distRoot = Join-Path $releaseRoot "Dist"
$zipPath = Join-Path $distRoot "QuickConnectManager-$Version.zip"
$pakSource = Join-Path $releaseRoot "Assets\QuickConnectManager_UI_P.pak"
$pakHashPath = Join-Path $releaseRoot "Assets\QuickConnectManager_UI_P.pak.sha256"
$thumbnailSource = Join-Path $releaseRoot "thumbnail.png"
$nexusImageSource = Join-Path $releaseRoot "NEXUS_IMAGE.png"
$modDestination = Join-Path $stageRoot "Pal\Binaries\Win64\UE4SS\Mods\QuickConnectManager"
$pakDestination = Join-Path $stageRoot "Pal\Content\Paks\~mods"
$scriptNames = @("config.lua", "connections.lua", "discovery.lua", "launch_ui.lua", "main.lua", "servers.lua")
$publicAuthor = "virtualbj$([char]0x00F6)rn"

foreach ($required in @(
    (Join-Path $modRoot "Info.json"),
    (Join-Path $modRoot "enabled.txt"),
    (Join-Path $modRoot "README.md"),
    $pakSource,
    $pakHashPath,
    $thumbnailSource,
    $nexusImageSource,
    (Join-Path $releaseRoot "README.txt"),
    (Join-Path $releaseRoot "CHANGELOG.md")
)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Required release input not found: $required"
    }
}
foreach ($scriptName in $scriptNames) {
    $required = Join-Path $modRoot "Scripts\$scriptName"
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Required runtime script not found: $required"
    }
}

$manifest = Get-Content -LiteralPath (Join-Path $modRoot "Info.json") -Raw -Encoding UTF8 | ConvertFrom-Json
if ($manifest.PackageName -ne "QuickConnectManager") {
    throw "Unexpected PackageName '$($manifest.PackageName)'."
}
if ($manifest.Version -ne $Version) {
    throw "Info.json version '$($manifest.Version)' does not match '$Version'."
}
if ($manifest.Author -ne $publicAuthor) {
    throw "Info.json must use the configured public author identity."
}
if ($manifest.Thumbnail -ne "thumbnail.png") {
    throw "Info.json Thumbnail must be thumbnail.png."
}
if (@($manifest.Dependencies).Count -ne 1 -or $manifest.Dependencies[0] -ne "UE4SSExperimentalPW") {
    throw "Info.json must contain only the UE4SSExperimentalPW dependency."
}
$luaRule = @($manifest.InstallRule | Where-Object Type -eq "Lua")
$pakRule = @($manifest.InstallRule | Where-Object Type -eq "Paks")
if ($luaRule.Count -ne 1 -or $luaRule[0].Targets.Count -ne 1 -or $luaRule[0].Targets[0] -ne "./Scripts") {
    throw "The Lua InstallRule must target ./Scripts."
}
if ($pakRule.Count -ne 1 -or $pakRule[0].Targets.Count -ne 1 -or $pakRule[0].Targets[0] -ne "./Paks/") {
    throw "The Paks InstallRule must target the Workshop Paks directory."
}
if ((Get-Item -LiteralPath $thumbnailSource).Length -ge 1MB) {
    throw "Thumbnail must be smaller than Steam's 1 MB limit."
}
$expectedPakHash = ((Get-Content -LiteralPath $pakHashPath -Raw).Trim() -split "\s+")[0].ToUpperInvariant()
$actualPakHash = (Get-FileHash -LiteralPath $pakSource -Algorithm SHA256).Hash
if ($actualPakHash -ne $expectedPakHash) {
    throw "Release PAK hash '$actualPakHash' does not match '$expectedPakHash'."
}

if (Test-Path -LiteralPath $stageRoot) {
    Remove-Item -LiteralPath $stageRoot -Recurse -Force
}
New-Item -ItemType Directory -Force -Path (Join-Path $modDestination "Scripts"), $pakDestination, $distRoot | Out-Null

Copy-Item -LiteralPath (Join-Path $modRoot "enabled.txt") -Destination $modDestination
Copy-Item -LiteralPath (Join-Path $modRoot "Info.json") -Destination $modDestination
Copy-Item -LiteralPath (Join-Path $modRoot "README.md") -Destination $modDestination
Copy-Item -LiteralPath $thumbnailSource -Destination (Join-Path $modDestination "thumbnail.png")
foreach ($scriptName in $scriptNames) {
    Copy-Item -LiteralPath (Join-Path $modRoot "Scripts\$scriptName") -Destination (Join-Path $modDestination "Scripts\$scriptName")
}
Copy-Item -LiteralPath $pakSource -Destination (Join-Path $pakDestination "QuickConnectManager_UI_P.pak")
Copy-Item -LiteralPath (Join-Path $releaseRoot "README.txt") -Destination $stageRoot
Copy-Item -LiteralPath (Join-Path $releaseRoot "CHANGELOG.md") -Destination $stageRoot

if (Test-Path -LiteralPath $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force
}
Compress-Archive -Path (Join-Path $stageRoot "*") -DestinationPath $zipPath -CompressionLevel Optimal
$zip = Get-Item -LiteralPath $zipPath
Copy-Item -LiteralPath $nexusImageSource -Destination (Join-Path $distRoot "QuickConnectManager-Nexus-Image.png") -Force
Write-Host "Built $($zip.FullName) ($($zip.Length) bytes)"
Write-Host "Prepared Nexus image: $(Join-Path $distRoot 'QuickConnectManager-Nexus-Image.png')"

if (-not $KeepStage) {
    Remove-Item -LiteralPath $stageRoot -Recurse -Force
}

$ErrorActionPreference = "Stop"

$projectRoot = $PSScriptRoot
$repoRoot = Split-Path -Parent $projectRoot
$toolsRoot = "F:\Hobby Project\Palworld Tools"
$unrealPak = Join-Path $toolsRoot "UnrealPak.exe"
$sourceRoot = Join-Path $repoRoot "QuickConnectManagerBlueprint"
$stageRoot = Join-Path $projectRoot "Stage"
$assetRelative = "Pal\Content\Mods\QuickConnectManager"
$assetStageRoot = Join-Path $stageRoot $assetRelative
$distRoot = Join-Path $projectRoot "Dist"
$pakOutput = Join-Path $distRoot "QuickConnectManager_UI_P.pak"
$responseFile = Join-Path $projectRoot "PakResponse.txt"

foreach ($required in @(
    $unrealPak,
    (Join-Path $sourceRoot "WBP_QuickConnectPanel.uasset"),
    (Join-Path $sourceRoot "WBP_QuickConnectPanel.uexp")
)) {
    if (-not (Test-Path -LiteralPath $required)) {
        throw "Required file not found: $required"
    }
}

New-Item -ItemType Directory -Force -Path $assetStageRoot | Out-Null
New-Item -ItemType Directory -Force -Path $distRoot | Out-Null

foreach ($extension in @(".uasset", ".uexp")) {
    $fileName = "WBP_QuickConnectPanel$extension"
    Copy-Item -LiteralPath (Join-Path $sourceRoot $fileName) -Destination (Join-Path $assetStageRoot $fileName) -Force
}

$stagePrefix = $stageRoot.TrimEnd("\") + "\"
$responseLines = Get-ChildItem -LiteralPath $assetStageRoot -File | ForEach-Object {
    $relative = $_.FullName.Substring($stagePrefix.Length).Replace("\", "/")
    '"{0}" "../../../{1}"' -f $_.FullName, $relative
}
[IO.File]::WriteAllLines($responseFile, $responseLines)

Remove-Item -LiteralPath $pakOutput -Force -ErrorAction SilentlyContinue
& $unrealPak $pakOutput "-Create=$responseFile" -compress
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $pakOutput)) {
    throw "UnrealPak failed to create $pakOutput"
}

& $unrealPak $pakOutput -List
Write-Host "Built: $pakOutput"

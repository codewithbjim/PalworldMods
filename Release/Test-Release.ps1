[CmdletBinding()]
param(
    [string]$Version,
    [string]$ZipPath,
    [string]$PakSource,
    [switch]$RequireLuaCompiler
)

$ErrorActionPreference = "Stop"
$releaseRoot = $PSScriptRoot
$repoRoot = Split-Path -Parent $releaseRoot
$modRoot = Join-Path $repoRoot "PerfectPlacement"

function Assert-ReleaseCondition {
    param(
        [bool]$Condition,
        [string]$Message
    )
    if (-not $Condition) {
        throw $Message
    }
}

function Get-Sha256 {
    param([string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

$manifestPath = Join-Path $modRoot "Info.json"
$darnMenuPath = Join-Path $modRoot "Scripts\darnmenu.lua"
$mainPath = Join-Path $modRoot "Scripts\main.lua"
$obsoleteMcmSchemaPath = Join-Path $modRoot "PerfectPlacement.modconfig.json"
$obsoleteMcmReaderPath = Join-Path $modRoot "Scripts\modconfig.lua"
Assert-ReleaseCondition (Test-Path -LiteralPath $manifestPath -PathType Leaf) `
    "Missing manifest: $manifestPath"
Assert-ReleaseCondition (Test-Path -LiteralPath $darnMenuPath -PathType Leaf) `
    "Missing DarnMenu adapter: $darnMenuPath"
Assert-ReleaseCondition (-not (Test-Path -LiteralPath $obsoleteMcmSchemaPath)) `
    "Obsolete Mod Config Menu schema must not be shipped."
Assert-ReleaseCondition (-not (Test-Path -LiteralPath $obsoleteMcmReaderPath)) `
    "Obsolete Mod Config Menu reader must not be shipped."

$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
if (-not $Version) {
    $Version = [string]$manifest.Version
}
if (-not $ZipPath) {
    $ZipPath = Join-Path $releaseRoot "Dist\PerfectPlacement-$Version.zip"
}
if (-not $PakSource) {
    $PakSource = Join-Path $repoRoot (
        "PerfectPlacementBlueprint\PalworldModdingKit\Saved\StagedBuilds\" +
        "Windows\Pal\Content\Paks\pakchunk1-Windows.pak"
    )
}

Assert-ReleaseCondition ($manifest.PackageName -eq "PerfectPlacement") `
    "Unexpected package name '$($manifest.PackageName)'."
Assert-ReleaseCondition ($manifest.Version -eq $Version) `
    "Info.json version '$($manifest.Version)' does not match '$Version'."
Assert-ReleaseCondition ($manifest.Dependencies -contains "DarnMenu") `
    "Info.json must declare the DarnMenu dependency."
$darnMenuSource = Get-Content -LiteralPath $darnMenuPath -Raw
Assert-ReleaseCondition ($darnMenuSource -match 'schemaVersion\s*=\s*8') `
    "DarnMenu schema version 8 was not found."
Assert-ReleaseCondition (
    $darnMenuSource -match 'target\s*=\s*"PerfectPlacement_user"'
) "DarnMenu target must be PerfectPlacement_user."
Assert-ReleaseCondition (
    $darnMenuSource -match 'title\s*=\s*"Movement settings \(cm\)"'
) "Movement settings must declare centimeters once in the section title."
Assert-ReleaseCondition (
    $darnMenuSource -notmatch 'note\s*=\s*"centimeters"'
) "Movement settings must not repeat the centimeters unit on each row."

$mainSource = Get-Content -LiteralPath $mainPath -Raw
$keycapRefresh = [regex]::Match(
    $mainSource,
    'local function refresh_keycaps_for_ui_host\(host\)(?<body>[\s\S]*?)\r?\nend'
)
Assert-ReleaseCondition $keycapRefresh.Success `
    "The UI-host keycap refresh function was not found."
Assert-ReleaseCondition (
    $keycapRefresh.Groups["body"].Value -notmatch
        'load_resolved_bindings|register_current_action_binding|register_action'
) "UI-host recreation must not reload or register keybindings."
Assert-ReleaseCondition (
    $mainSource -notmatch 'refresh_bindings_from_darnmenu'
) "The obsolete per-UI-host binding refresh must not be restored."

$requiredSources = @(
    "enabled.txt",
    "Info.json",
    "README.md",
    "Scripts\config.lua",
    "Scripts\darnmenu.lua",
    "Scripts\keybindings.lua",
    "Scripts\main.lua"
)
foreach ($relativePath in $requiredSources) {
    $sourcePath = Join-Path $modRoot $relativePath
    Assert-ReleaseCondition (Test-Path -LiteralPath $sourcePath -PathType Leaf) `
        "Missing release source: $sourcePath"
}
Assert-ReleaseCondition (Test-Path -LiteralPath $PakSource -PathType Leaf) `
    "Missing staged PAK: $PakSource"
Assert-ReleaseCondition (Test-Path -LiteralPath $ZipPath -PathType Leaf) `
    "Missing release archive: $ZipPath"

foreach ($scriptPath in Get-ChildItem -LiteralPath $releaseRoot -Filter "*.ps1") {
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile(
        $scriptPath.FullName,
        [ref]$tokens,
        [ref]$errors
    ) | Out-Null
    Assert-ReleaseCondition ($errors.Count -eq 0) `
        "PowerShell syntax error in $($scriptPath.Name): $($errors[0].Message)"
}

$luaCompiler = Get-Command "luac" -ErrorAction SilentlyContinue
if ($luaCompiler) {
    foreach ($luaPath in Get-ChildItem -LiteralPath (Join-Path $modRoot "Scripts") -Filter "*.lua") {
        & $luaCompiler.Source -p $luaPath.FullName
        Assert-ReleaseCondition ($LASTEXITCODE -eq 0) `
            "Lua syntax validation failed: $($luaPath.FullName)"
    }
} elseif ($RequireLuaCompiler) {
    throw "luac is required but was not found on PATH."
} else {
    Write-Warning "luac was not found; complete the Lua syntax item in PRE_DEPLOY_CHECKLIST.md."
}

Push-Location $repoRoot
try {
    & git diff --check
    Assert-ReleaseCondition ($LASTEXITCODE -eq 0) "git diff --check failed."
} finally {
    Pop-Location
}

$temporaryRoot = Join-Path (
    [System.IO.Path]::GetTempPath()
) ("PerfectPlacement-release-test-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $temporaryRoot | Out-Null
try {
    Expand-Archive -LiteralPath $ZipPath -DestinationPath $temporaryRoot

    $archiveModRoot = Join-Path $temporaryRoot (
        "Pal\Binaries\Win64\UE4SS\Mods\PerfectPlacement"
    )
    foreach ($relativePath in $requiredSources) {
        $sourcePath = Join-Path $modRoot $relativePath
        $archivePath = Join-Path $archiveModRoot $relativePath
        Assert-ReleaseCondition (Test-Path -LiteralPath $archivePath -PathType Leaf) `
            "Archive is missing: $relativePath"
        Assert-ReleaseCondition (
            (Get-Sha256 $sourcePath) -eq (Get-Sha256 $archivePath)
        ) "Archive contains stale content: $relativePath"
    }

    $archiveManifest = Get-Content -LiteralPath (
        Join-Path $archiveModRoot "Info.json"
    ) -Raw | ConvertFrom-Json
    Assert-ReleaseCondition ($archiveManifest.Version -eq $Version) `
        "Archive manifest version '$($archiveManifest.Version)' is stale."

    $archivePak = Join-Path $temporaryRoot (
        "Pal\Content\Paks\LogicMods\PerfectPlacement.pak"
    )
    Assert-ReleaseCondition (Test-Path -LiteralPath $archivePak -PathType Leaf) `
        "Archive is missing PerfectPlacement.pak."
    Assert-ReleaseCondition (
        (Get-Sha256 $PakSource) -eq (Get-Sha256 $archivePak)
    ) "Archive contains a stale or unexpected PerfectPlacement.pak."

    foreach ($releaseFile in @("CHANGELOG.md", "README.txt")) {
        $sourcePath = Join-Path $releaseRoot $releaseFile
        $archivePath = Join-Path $temporaryRoot $releaseFile
        Assert-ReleaseCondition (Test-Path -LiteralPath $archivePath -PathType Leaf) `
            "Archive is missing $releaseFile."
        Assert-ReleaseCondition (
            (Get-Sha256 $sourcePath) -eq (Get-Sha256 $archivePath)
        ) "Archive contains stale content: $releaseFile"
    }
} finally {
    if (Test-Path -LiteralPath $temporaryRoot) {
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
    }
}

Write-Host ""
Write-Host "Automated release gate passed for Perfect Placement $Version."
Write-Host "Archive: $ZipPath"
Write-Host "SHA256: $(Get-Sha256 $ZipPath)"
Write-Host "Complete and record the manual tests in PRE_DEPLOY_CHECKLIST.md before publishing."

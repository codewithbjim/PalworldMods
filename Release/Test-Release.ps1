[CmdletBinding()]
param(
    [string]$Version,
    [string]$ZipPath,
    [string]$PakSource,
    [string]$WorkshopPath,
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
$thumbnailPath = Join-Path $releaseRoot "thumbnail.png"
$pakHashPath = Join-Path $releaseRoot "Assets\PerfectPlacement.pak.sha256"
$changelogPath = Join-Path $releaseRoot "CHANGELOG.md"
$releaseReadmePath = Join-Path $releaseRoot "README.txt"
$workshopChangelogPath = Join-Path $releaseRoot "WORKSHOP_CHANGELOG.txt"
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
Assert-ReleaseCondition (Test-Path -LiteralPath $thumbnailPath -PathType Leaf) `
    "Missing release thumbnail: $thumbnailPath"
Assert-ReleaseCondition (Test-Path -LiteralPath $pakHashPath -PathType Leaf) `
    "Missing release PAK checksum: $pakHashPath"

$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
if (-not $Version) {
    $Version = [string]$manifest.Version
}
if (-not $ZipPath) {
    $ZipPath = Join-Path $releaseRoot "Dist\PerfectPlacement-$Version.zip"
}
if (-not $WorkshopPath) {
    $WorkshopPath = Join-Path $releaseRoot "Dist\Workshop-$Version"
}
if (-not $PakSource) {
    $PakSource = Join-Path $releaseRoot "Assets\PerfectPlacement.pak"
}

Assert-ReleaseCondition ($manifest.PackageName -eq "PerfectPlacement") `
    "Unexpected package name '$($manifest.PackageName)'."
Assert-ReleaseCondition ($manifest.Version -eq $Version) `
    "Info.json version '$($manifest.Version)' does not match '$Version'."
Assert-ReleaseCondition ($manifest.Dependencies -contains "DarnMenu") `
    "Info.json must declare the DarnMenu dependency."
Assert-ReleaseCondition ($manifest.Thumbnail -eq "thumbnail.png") `
    "Info.json Thumbnail must be thumbnail.png."
Assert-ReleaseCondition ((Get-Item -LiteralPath $thumbnailPath).Length -lt 1MB) `
    "Release thumbnail must be smaller than 1 MB."
$changelogSource = Get-Content -LiteralPath $changelogPath -Raw
$firstChangelogVersion = [regex]::Match(
    $changelogSource,
    '(?m)^##\s+(.+?)\s*$'
).Groups[1].Value
Assert-ReleaseCondition ($firstChangelogVersion -eq $Version) `
    "The first CHANGELOG.md version '$firstChangelogVersion' is stale."
$releaseReadmeSource = Get-Content -LiteralPath $releaseReadmePath -Raw
Assert-ReleaseCondition (
    $releaseReadmeSource -match [regex]::Escape($Version.ToUpperInvariant())
) "README.txt does not identify $Version."
$firstWorkshopChangelogLine = (
    Get-Content -LiteralPath $workshopChangelogPath |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        Select-Object -First 1
)
Assert-ReleaseCondition (
    $firstWorkshopChangelogLine -match [regex]::Escape($Version)
) "WORKSHOP_CHANGELOG.txt does not begin with $Version."
$darnMenuSource = Get-Content -LiteralPath $darnMenuPath -Raw
Assert-ReleaseCondition ($darnMenuSource -match 'schemaVersion\s*=\s*11') `
    "DarnMenu schema version 11 was not found."
Assert-ReleaseCondition (
    $darnMenuSource -match 'target\s*=\s*"PerfectPlacement_user"'
) "DarnMenu target must be PerfectPlacement_user."
Assert-ReleaseCondition (
    $darnMenuSource -match 'title\s*=\s*"Movement settings"'
) "The plain Movement settings section title was not found."
Assert-ReleaseCondition (
    $darnMenuSource -notmatch 'note\s*=\s*"centimeters"'
) "Movement settings must not use per-row note labels for units."
Assert-ReleaseCondition (
    ([regex]::Matches(
        $darnMenuSource,
        'help\s*=\s*"In centimeters\."'
    )).Count -eq 5
) "Exactly five distance settings must show centimeters in their help text."
Assert-ReleaseCondition (
    $darnMenuSource -notmatch 'title\s*=\s*"Interface"'
) "The Interface section must remain hidden from DarnMenu."
Assert-ReleaseCondition (
    $darnMenuSource -match
        'path\s*=\s*"freeze_to_piece"[\s\S]*?kind\s*=\s*"keychord"'
) "DarnMenu must expose the copy-and-freeze key chord."

$mainSource = Get-Content -LiteralPath $mainPath -Raw
Assert-ReleaseCondition (
    $mainSource -match [regex]::Escape("Loaded Perfect Placement $Version")
) "The Lua startup version does not match '$Version'."
Assert-ReleaseCondition (
    $mainSource -match
        'register_action\("freeze_to_piece",\s*freeze_to_looked_at_build_piece\)'
) "The copy-and-freeze action is not registered."
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
Assert-ReleaseCondition (
    $mainSource -match 'BuildingSurfaceMaterialSet'
) "Frozen validity refresh must use Palworld's live surface material set."
Assert-ReleaseCondition (
    $mainSource -match 'mesh:SetMaterial\(material_index,\s*material\)'
) "Frozen validity refresh must repaint each preview material slot."
Assert-ReleaseCondition (
    $mainSource -match 'widget:UpdateDisplay\(\)'
) "Frozen validity refresh must update Palworld's placement warning."
Assert-ReleaseCondition (
    ([regex]::Matches(
        $mainSource,
        'ExecuteInGameThread\s*\('
    )).Count -eq 2
) "Direct game-thread calls must remain isolated inside the retained wrapper."
Assert-ReleaseCondition (
    $mainSource -notmatch 'ExecuteWithDelay\s*\('
) "All delayed callbacks must use the retained callback wrapper."
Assert-ReleaseCondition (
    $mainSource -match
        'completed_async_callbacks\[callback_id\]\s*=\s*true'
) "Executed callbacks must remain retained until bounded-history pruning."
Assert-ReleaseCondition (
    $mainSource -match 'EGameThreadMethod\.ProcessEvent'
) "Immediate PP callbacks must prefer the isolated ProcessEvent queue."
Assert-ReleaseCondition (
    $mainSource -match 'set_actor_transform_verified'
) "Transform calls must verify success after UE4SS FHitResult marshal errors."
Assert-ReleaseCondition (
    $mainSource -match 'registered_keybind_callbacks'
) "Registered keybind callbacks must keep a module-lifetime Lua reference."
Assert-ReleaseCondition (
    $mainSource -match
        'if\s+status_ok\s+and\s+in_building_mode\s+and\s+has_preview\s+then\s+' +
        '[\s\S]*?construction_ui_active\s*=\s*' +
        'construction_ui_is_active\(allow_ui_fallback_scan\)'
) "Normal gameplay must not scan for construction widgets while build mode is inactive."
$constructionUiFunction = [regex]::Match(
    $mainSource,
    'local function construction_ui_is_active\(allow_fallback_scan\)' +
        '(?<body>[\s\S]*?)\r?\nend\r?\n\r?\n' +
        'local function should_release_locked_preview'
)
Assert-ReleaseCondition $constructionUiFunction.Success `
    "The construction UI lifecycle function was not found."
Assert-ReleaseCondition (
    $constructionUiFunction.Groups["body"].Value -match
        'if\s+cached_visibility\s*==\s*true\s+or\s+' +
        'not\s+allow_fallback_scan\s+then\s+' +
        'return\s+cached_visibility'
) "Construction UI checks must reuse the cached widget instead of repeatedly using FindAllOf."
Assert-ReleaseCondition (
    $constructionUiFunction.Groups["body"].Value -match
        'if\s+not\s+allow_fallback_scan\s+then\s+return\s+nil'
) "A class-wide construction-widget scan must require a new preview context."
Assert-ReleaseCondition (
    $mainSource -match
        'if\s+lifecycle_game_thread_pending\s+then\s+return'
) "The lifecycle monitor must coalesce pending game-thread checks."

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
$expectedPakHash = (
    (Get-Content -LiteralPath $pakHashPath -Raw).Trim() -split "\s+"
)[0].ToUpperInvariant()
Assert-ReleaseCondition (
    (Get-Sha256 $PakSource) -eq $expectedPakHash
) "Release PAK does not match its pinned SHA-256."
Assert-ReleaseCondition (Test-Path -LiteralPath $ZipPath -PathType Leaf) `
    "Missing release archive: $ZipPath"
Assert-ReleaseCondition (Test-Path -LiteralPath $WorkshopPath -PathType Container) `
    "Missing Workshop package: $WorkshopPath"

$workshopManifestPath = Join-Path $WorkshopPath "Info.json"
Assert-ReleaseCondition (
    Test-Path -LiteralPath $workshopManifestPath -PathType Leaf
) "Workshop package is missing Info.json."
$workshopManifest =
    Get-Content -LiteralPath $workshopManifestPath -Raw | ConvertFrom-Json
Assert-ReleaseCondition ($workshopManifest.Version -eq $Version) `
    "Workshop manifest version '$($workshopManifest.Version)' is stale."
Assert-ReleaseCondition (
    -not (Test-Path -LiteralPath (
        Join-Path $WorkshopPath "PerfectPlacement.modconfig.json"
    ))
) "Workshop package contains the obsolete Mod Config Menu schema."
foreach ($scriptName in @("main.lua", "config.lua", "keybindings.lua", "darnmenu.lua")) {
    $sourceScript = Join-Path $modRoot "Scripts\$scriptName"
    $workshopScript = Join-Path $WorkshopPath "Scripts\$scriptName"
    Assert-ReleaseCondition (
        Test-Path -LiteralPath $workshopScript -PathType Leaf
    ) "Workshop package is missing Scripts\$scriptName."
    Assert-ReleaseCondition (
        (Get-Sha256 $sourceScript) -eq (Get-Sha256 $workshopScript)
    ) "Workshop package contains stale Scripts\$scriptName."
}
$workshopPak = Join-Path $WorkshopPath "LogicMods\PerfectPlacement.pak"
Assert-ReleaseCondition (
    Test-Path -LiteralPath $workshopPak -PathType Leaf
) "Workshop package is missing LogicMods\PerfectPlacement.pak."
Assert-ReleaseCondition (
    (Get-Sha256 $PakSource) -eq (Get-Sha256 $workshopPak)
) "Workshop package contains a stale or unexpected PerfectPlacement.pak."
$workshopThumbnail = Join-Path $WorkshopPath "thumbnail.png"
Assert-ReleaseCondition (
    Test-Path -LiteralPath $workshopThumbnail -PathType Leaf
) "Workshop package is missing thumbnail.png."
Assert-ReleaseCondition (
    (Get-Sha256 $thumbnailPath) -eq (Get-Sha256 $workshopThumbnail)
) "Workshop package contains a stale or unexpected thumbnail.png."

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
    $archiveThumbnail = Join-Path $archiveModRoot "thumbnail.png"
    Assert-ReleaseCondition (
        (Test-Path -LiteralPath $archiveThumbnail -PathType Leaf)
    ) "Archive is missing thumbnail.png."
    Assert-ReleaseCondition (
        (Get-Sha256 $thumbnailPath) -eq (Get-Sha256 $archiveThumbnail)
    ) "Archive contains a stale or unexpected thumbnail.png."

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

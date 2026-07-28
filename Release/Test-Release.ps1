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
$configPath = Join-Path $modRoot "Scripts\config.lua"
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
Assert-ReleaseCondition (Test-Path -LiteralPath $configPath -PathType Leaf) `
    "Missing default config: $configPath"
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
Assert-ReleaseCondition ($manifest.Dependencies -contains "UE4SSExperimentalPW") `
    "Info.json must declare the official UE4SS Experimental package dependency."
Assert-ReleaseCondition (-not ($manifest.Dependencies -contains "DarnMenu")) `
    "DarnMenu must remain an optional integration, not a hard package dependency."
Assert-ReleaseCondition (@($manifest.Dependencies).Count -eq 1) `
    "Info.json must contain only the UE4SSExperimentalPW hard dependency."
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
foreach ($publicChangelog in @($changelogPath, $workshopChangelogPath)) {
    $wrappedLine = Select-String `
        -LiteralPath $publicChangelog `
        -Pattern '^[ \t]+\S' |
        Select-Object -First 1
    if ($wrappedLine) {
        throw (
            "Hard-wrapped changelog line: {0}:{1}" -f
            $wrappedLine.Path,
            $wrappedLine.LineNumber
        )
    }
}
$darnMenuSource = Get-Content -LiteralPath $darnMenuPath -Raw
$configSource = Get-Content -LiteralPath $configPath -Raw
Assert-ReleaseCondition (
    $darnMenuSource -match 'local\s+SCHEMA_VERSION\s*=\s*13'
) "DarnMenu schema constant version 13 was not found."
Assert-ReleaseCondition ($darnMenuSource -match 'schemaVersion\s*=\s*13') `
    "Embedded DarnMenu schema version 13 was not found."
Assert-ReleaseCondition (
    $darnMenuSource -match 'target\s*=\s*"PerfectPlacement_user"'
) "DarnMenu target must be PerfectPlacement_user."
Assert-ReleaseCondition (
    $darnMenuSource -match 'live\s*=\s*false'
) "Perfect Placement settings must remain marked relaunch-only until runtime reload is implemented."
Assert-ReleaseCondition (
    $darnMenuSource -match
        'applyNote\s*=\s*"Saved\. Restart Palworld to apply changes\."'
) "DarnMenu must accurately state that every Perfect Placement change requires a restart."
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
Assert-ReleaseCondition (
    $darnMenuSource -match
        'path\s*=\s*"refresh_frozen_validity"[\s\S]*?kind\s*=\s*"bool"'
) "DarnMenu must expose the frozen-validity toggle."
Assert-ReleaseCondition (
    $darnMenuSource -match 'refresh_frozen_validity\s*=\s*true'
) "Frozen-validity feedback must default on in DarnMenu."
Assert-ReleaseCondition (
    $configSource -match 'refresh_frozen_feedback\s*=\s*true'
) "Frozen-validity feedback must default on in config.lua."

$mainSource = Get-Content -LiteralPath $mainPath -Raw
Assert-ReleaseCondition (
    $mainSource -match [regex]::Escape("Loaded Perfect Placement $Version")
) "The Lua startup version does not match '$Version'."
Assert-ReleaseCondition (
    $mainSource -match
        [regex]::Escape("Companion key-guide UI bridge revision 24 loaded.")
) "The Lua bridge revision does not match the rc.3 PAK."
Assert-ReleaseCondition (
    $mainSource -match
        'register_action\("freeze_to_piece",\s*freeze_to_looked_at_build_piece\)'
) "The copy-and-freeze action is not registered."
Assert-ReleaseCondition (
    $mainSource -match
        'freeze_to_piece\s*=\s*\{\s*"CopyFreezeChord"\s*\}'
) "The companion guide must populate its copy-and-freeze chord widget."
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
        'Config\.validity\.refresh_frozen_feedback\s*~=\s*true'
    )).Count -eq 2
) "Both frozen-validity entry points must be disabled unless explicitly enabled."
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
    $mainSource -match 'EGameThreadMethod\.EngineTick'
) "Immediate PP callbacks must use the EngineTick queue."
Assert-ReleaseCondition (
    $mainSource -notmatch 'EGameThreadMethod\.ProcessEvent'
) "Perfect Placement must never force work through the shared ProcessEvent queue."
Assert-ReleaseCondition (
    $mainSource -match 'ExecuteInGameThreadWithDelay'
) "Delayed work must prefer UE4SS-owned game-thread actions."
Assert-ReleaseCondition (
    $mainSource -match 'set_actor_transform_verified'
) "Transform calls must verify success after UE4SS FHitResult marshal errors."
Assert-ReleaseCondition (
    $mainSource -match 'registered_keybind_callbacks'
) "Registered keybind callbacks must keep a module-lifetime Lua reference."
Assert-ReleaseCondition (
    $mainSource -notmatch 'IDLE_UI_REFRESH_TICKS|BUILDER_FALLBACK_RETRY_TICKS'
) "Normal gameplay must not retain an idle guide-poll cadence."
$uiHostCallback = [regex]::Match(
    $mainSource,
    'ui_host_notify_callback\s*=\s*function\(\)' +
        '(?<body>[\s\S]*?)\r?\nend\r?\n\r?\nconstruction_ui_notify_callback'
)
Assert-ReleaseCondition $uiHostCallback.Success `
    "The companion UI host callback was not found."
Assert-ReleaseCondition (
    $uiHostCallback.Groups["body"].Value -match
        'find_active_build_context\(false\)[\s\S]*?' +
        'live_frozen\s*=\s*state\s*==\s*State\.EDITING[\s\S]*?' +
        'live_unfrozen\s*=\s*is_valid\(active_component\)[\s\S]*?' +
        'construction_ui_is_active\(false\)\s*==\s*true[\s\S]*?' +
        'update_perfect_placement_ui\(\s*' +
        'live_frozen,\s*false,\s*' +
        'not\s*\(live_frozen\s+or\s+live_unfrozen\)\s*\)'
) "Companion UI creation must remain hidden without a live local build preview."
$keyguideHookFunction = [regex]::Match(
    $mainSource,
    'local function ensure_keyguide_hook\(\)' +
        '(?<body>[\s\S]*?)\r?\nend\r?\n\r?\n' +
        'local function ensure_construction_ui_hooks'
)
Assert-ReleaseCondition $keyguideHookFunction.Success `
    "The construction key-guide hook function was not found."
Assert-ReleaseCondition (
    $keyguideHookFunction.Groups["body"].Value -match
        'RegisterHook\(\s*KEYGUIDE_SETUP_PATH,\s*keyguide_hook_callback\s*\)'
) "The Blueprint key-guide hook must use one meaningful callback."
Assert-ReleaseCondition (
    $keyguideHookFunction.Groups["body"].Value -match
        'keyguide_hook_registered\s*=\s*\{\s*' +
        'callback\s*=\s*keyguide_hook_callback,\s*' +
        'pre_id\s*=\s*pre_id,\s*post_id\s*=\s*post_id,'
) "The key-guide hook must retain its callback and both UE4SS hook IDs."
$constructionHookFunction = [regex]::Match(
    $mainSource,
    'local function ensure_construction_ui_hooks\(\)' +
        '(?<body>[\s\S]*?)\r?\nend\r?\n\r?\n' +
        'update_construction_hotkey_guide\s*='
)
Assert-ReleaseCondition $constructionHookFunction.Success `
    "The construction lifecycle hook function was not found."
Assert-ReleaseCondition (
    $constructionHookFunction.Groups["body"].Value -match
        'RegisterHook\(\s*function_path,\s*callback\s*\)'
) "Construction lifecycle hooks must use one meaningful Blueprint callback."
Assert-ReleaseCondition (
    $constructionHookFunction.Groups["body"].Value -match
        'construction_ui_hooks\[function_path\]\s*=\s*\{\s*' +
        'callback\s*=\s*callback,\s*pre_id\s*=\s*pre_id,\s*' +
        'post_id\s*=\s*post_id,'
) "Construction lifecycle hooks must retain callbacks and both hook IDs."
foreach ($eventName in @(
    "ReturnToMainMenu",
    "OnEsc",
    "ChangeMode",
    "Destruct",
    "OpenMenu_Internal",
    "OpenBuildMenu",
    "OpenBuildRadialMenu",
    "OpenBuildRadialMenuWithSelectedIndex",
    "OnTriggerEscape"
)) {
    Assert-ReleaseCondition (
        $constructionHookFunction.Groups["body"].Value -match
            [regex]::Escape('"' + $eventName + '"')
    ) "Missing construction close/menu event hook: $eventName."
}
Assert-ReleaseCondition (
    $constructionHookFunction.Groups["body"].Value -match
        'construction_root\s*\.\.\s*"Setup",\s*"Setup",\s*true'
) "Construction Setup must restore the verified unfrozen guide."
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
        'local\s+ui_reports_exit\s*=\s*locked_construction_ui_was_active\s+' +
        'and\s+construction_ui_active\s*==\s*false'
) "Construction UI visibility must be edge-triggered before it can auto-release Freeze."
Assert-ReleaseCondition (
    $mainSource -notmatch
        'observed_construction_exit\s*=\s*\(mode_ok\s+and\s+not\s+' +
        'in_building_mode\)\s+or\s+construction_ui_active\s*==\s*false'
) "A hidden construction widget must not independently auto-release Freeze."
$lifecycleMonitorFunction = [regex]::Match(
    $mainSource,
    'local function start_lifecycle_monitor\(\)' +
        '(?<body>[\s\S]*?)\r?\nend\r?\n\r?\n' +
        'local function refresh_overlap_component'
)
Assert-ReleaseCondition $lifecycleMonitorFunction.Success `
    "The lifecycle monitor function was not found."
Assert-ReleaseCondition (
    $lifecycleMonitorFunction.Groups["body"].Value -match
        'if\s+state\s*~=\s*State\.EDITING\s+then\s+' +
        'lifecycle_monitor_started\s*=\s*false\s+' +
        'return\s+true'
) "The lifecycle worker must stop after leaving frozen editing."
Assert-ReleaseCondition (
    $lifecycleMonitorFunction.Groups["body"].Value -match
        'if\s+state\s*~=\s*State\.EDITING\s+' +
        'or\s+freeze_transition_input_locked'
) "A queued lifecycle callback must become a no-op after leaving frozen editing."
Assert-ReleaseCondition (
    $mainSource -match
        'if\s+lifecycle_game_thread_pending\s+then\s+return'
) "The lifecycle monitor must coalesce pending game-thread checks."
$releaseFunction = [regex]::Match(
    $mainSource,
    'release_preview\s*=\s*function\(reason\)' +
        '(?<body>[\s\S]*?)\r?\nend\r?\n\r?\n' +
        'local function move_preview'
)
Assert-ReleaseCondition $releaseFunction.Success `
    "The preview release function was not found."
Assert-ReleaseCondition (
    $releaseFunction.Groups["body"].Value -match
        'show_unfreeze_toast\s*=\s*reason\s*==\s*"manual"[\s\S]*?' +
        'update_construction_hotkey_guide\(\s*false,\s*' +
        'show_unfreeze_toast,\s*left_construction\s+or\s+no_active_preview\s*\)'
) "Manual Unfreeze must restore the guide while inactive previews stay hidden."
Assert-ReleaseCondition (
    $releaseFunction.Groups["body"].Value -match
        'string\.find\(\s*rendered_reason,\s*"Palworld action:"'
) "Construction action releases must hide the companion guide."
Assert-ReleaseCondition (
    $mainSource -match
        'construction_ui_notify_callback\s*=\s*function\(\)\s*' +
        'ensure_keyguide_hook\(\)\s*ensure_construction_ui_hooks\(\)\s*' +
        'ui_host_notify_callback\(\)'
) "Construction widget creation must retry event-hook registration."
Assert-ReleaseCondition (
    ([regex]::Matches(
        $mainSource,
        'start_lifecycle_monitor\(\)'
    )).Count -eq 2
) "The lifecycle monitor must start only from the function definition and Freeze."

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
    (Get-Sha256 $manifestPath) -eq (Get-Sha256 $workshopManifestPath)
) "Workshop Info.json must match source Info.json byte-for-byte."
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

foreach ($luaPath in Get-ChildItem -LiteralPath (
    Join-Path $modRoot "Scripts"
) -Filter "*.lua") {
    $persistentMainChunkLocals = 0
    foreach ($line in Get-Content -LiteralPath $luaPath.FullName) {
        if ($line -match "^local\s+function\s+[A-Za-z_][A-Za-z0-9_]*") {
            $persistentMainChunkLocals++
            continue
        }
        if ($line -notmatch "^local\s+(.+?)(?:\s*=|$)") {
            continue
        }
        $declaredNames = @(
            $Matches[1] -split "," |
                ForEach-Object { $_.Trim() } |
                Where-Object { $_ -match "^[A-Za-z_][A-Za-z0-9_]*$" }
        )
        $persistentMainChunkLocals += $declaredNames.Count
    }
    Assert-ReleaseCondition ($persistentMainChunkLocals -le 180) (
        "$($luaPath.Name) declares $persistentMainChunkLocals persistent " +
        "main-chunk locals; keep every script at or below 180 so UE4SS " +
        "stays under Lua's hard 200-local compile limit."
    )
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

[CmdletBinding()]
param(
    [string]$Version,
    [string]$ZipPath,
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
$gamepadPath = Join-Path $modRoot "Scripts\gamepad.lua"
$keybindingsPath = Join-Path $modRoot "Scripts\keybindings.lua"
$companionBridgePath = Join-Path $modRoot "Scripts\companion_bridge.lua"
$mainPath = Join-Path $modRoot "Scripts\main.lua"
$runtimePath = Join-Path $modRoot "Scripts\runtime.lua"
$runtimeTestPath = Join-Path $releaseRoot "Tests\Test-Runtime.lua"
$thumbnailPath = Join-Path $releaseRoot "thumbnail.png"
$nativePakPath = Join-Path $releaseRoot "Assets\PerfectPlacement_NativeUI_P.pak"
$nativePakHashPath = Join-Path $releaseRoot "Assets\PerfectPlacement_NativeUI_P.pak.sha256"
$nativeScaffoldBuilderPath = Join-Path $repoRoot "NativeUI\Build-Scaffold.ps1"
$nativePakBuilderPath = Join-Path $repoRoot "NativeUI\Build-Pak.ps1"
$nativeCookedRoot = Join-Path $repoRoot "NativeUI\Cooked"
$changelogPath = Join-Path $releaseRoot "CHANGELOG.md"
$releaseReadmePath = Join-Path $releaseRoot "README.txt"
$workshopChangelogPath = Join-Path $releaseRoot "WORKSHOP_CHANGELOG.txt"
$nexusChangelogPath = Join-Path $releaseRoot "NEXUS_VERSION_CHANGELOG.txt"
$nexusPublisherPath = Join-Path $releaseRoot "publish-nexus.ps1"
$obsoleteMcmSchemaPath = Join-Path $modRoot "PerfectPlacement.modconfig.json"
$obsoleteMcmReaderPath = Join-Path $modRoot "Scripts\modconfig.lua"
Assert-ReleaseCondition (Test-Path -LiteralPath $manifestPath -PathType Leaf) `
    "Missing manifest: $manifestPath"
Assert-ReleaseCondition (Test-Path -LiteralPath $darnMenuPath -PathType Leaf) `
    "Missing DarnMenu adapter: $darnMenuPath"
Assert-ReleaseCondition (Test-Path -LiteralPath $configPath -PathType Leaf) `
    "Missing default config: $configPath"
Assert-ReleaseCondition (Test-Path -LiteralPath $gamepadPath -PathType Leaf) `
    "Missing gamepad input adapter: $gamepadPath"
Assert-ReleaseCondition (Test-Path -LiteralPath $companionBridgePath -PathType Leaf) `
    "Missing consolidated companion bridge loader: $companionBridgePath"
Assert-ReleaseCondition (Test-Path -LiteralPath $runtimePath -PathType Leaf) `
    "Missing game-thread runtime helper: $runtimePath"
Assert-ReleaseCondition (Test-Path -LiteralPath $runtimeTestPath -PathType Leaf) `
    "Missing game-thread runtime regression harness: $runtimeTestPath"
Assert-ReleaseCondition (-not (Test-Path -LiteralPath $obsoleteMcmSchemaPath)) `
    "Obsolete Mod Config Menu schema must not be shipped."
Assert-ReleaseCondition (-not (Test-Path -LiteralPath $obsoleteMcmReaderPath)) `
    "Obsolete Mod Config Menu reader must not be shipped."
Assert-ReleaseCondition (Test-Path -LiteralPath $thumbnailPath -PathType Leaf) `
    "Missing release thumbnail: $thumbnailPath"
Assert-ReleaseCondition (Test-Path -LiteralPath $nativePakPath -PathType Leaf) `
    "Missing native UI PAK: $nativePakPath"
Assert-ReleaseCondition (Test-Path -LiteralPath $nativePakHashPath -PathType Leaf) `
    "Missing native UI PAK checksum: $nativePakHashPath"
Assert-ReleaseCondition (Test-Path -LiteralPath $nativeScaffoldBuilderPath -PathType Leaf) `
    "Missing native UI scaffold builder: $nativeScaffoldBuilderPath"
Assert-ReleaseCondition (Test-Path -LiteralPath $nativePakBuilderPath -PathType Leaf) `
    "Missing native UI PAK builder: $nativePakBuilderPath"
foreach ($relativeAsset in @(
    "Pal\Content\Mods\PerfectPlacement\ModActor.uasset",
    "Pal\Content\Mods\PerfectPlacement\ModActor.uexp",
    "Pal\Content\Mods\PerfectPlacement\WBP_PerfectPlacement_KeyGuide.uasset",
    "Pal\Content\Mods\PerfectPlacement\WBP_PerfectPlacement_KeyGuide.uexp",
    "Pal\Content\Mods\PerfectPlacement\BP_PP_FrozenGamepadInput.uasset",
    "Pal\Content\Mods\PerfectPlacement\BP_PP_UnfrozenGamepadInput.uasset"
)) {
    $cookedAsset = Join-Path $nativeCookedRoot $relativeAsset
    Assert-ReleaseCondition (Test-Path -LiteralPath $cookedAsset -PathType Leaf) `
        "Missing cooked companion asset: $cookedAsset"
}
Assert-ReleaseCondition (Test-Path -LiteralPath $nexusPublisherPath -PathType Leaf) `
    "Missing Nexus publisher: $nexusPublisherPath"
Assert-ReleaseCondition (Test-Path -LiteralPath $nexusChangelogPath -PathType Leaf) `
    "Missing compact Nexus version changelog: $nexusChangelogPath"

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
foreach ($type in @("Lua", "Paks")) {
    Assert-ReleaseCondition ($manifest.InstallRule.Type -contains $type) `
        "Info.json is missing the $type InstallRule."
}
Assert-ReleaseCondition (-not ($manifest.InstallRule.Type -contains "LogicMods")) `
    "Info.json must retire the LogicMods InstallRule."
$nativePaksRule = $manifest.InstallRule | Where-Object Type -eq "Paks"
Assert-ReleaseCondition (
    $nativePaksRule.Targets.Count -eq 1 -and
    $nativePaksRule.Targets[0] -eq "./Paks/PerfectPlacement_NativeUI_P.pak"
) "The Paks InstallRule must target the native UI PAK directly."
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
$nexusPublisherSource = Get-Content -LiteralPath $nexusPublisherPath -Raw
$nexusChangelogSource = (
    Get-Content -LiteralPath $nexusChangelogPath -Raw
).TrimEnd("`r", "`n") -replace "`r`n", "`n"
Assert-ReleaseCondition (-not [string]::IsNullOrWhiteSpace($nexusChangelogSource)) `
    "Nexus version changelog must not be empty."
Assert-ReleaseCondition ($nexusChangelogSource.Length -le 255) `
    "The entire Nexus version changelog must be 255 characters or fewer."
Assert-ReleaseCondition ($nexusChangelogSource -notmatch '(?m)^\s*$') `
    "Nexus version changelog must not contain blank lines."
Assert-ReleaseCondition (
    $nexusChangelogSource -notmatch '(?m)^\s*(?:[-*#]|\d+[.)])\s*'
) "Nexus version changelog must use plain lines without headings or bullets."
Assert-ReleaseCondition (
    $nexusPublisherSource -match
        'Invoke-RestMethod\s+-Method\s+Post\s+-Uri\s+"\$baseUrl/mods/\$modGlobalId/changelogs"'
) "Nexus publisher must publish the version changelog through the dedicated v3 endpoint."
Assert-ReleaseCondition (
    $nexusPublisherSource -match
        '\$existing\.PSObject\.Properties\.Name\s+-contains\s+\$Version'
) "Nexus publisher must refuse to append duplicate changelog entries."
Assert-ReleaseCondition (
    $nexusPublisherSource -match
        'NEXUS_VERSION_CHANGELOG\.txt'
) "Nexus publisher must load the compact version changelog file by default."
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
    $overlongEntry = Get-Content -LiteralPath $publicChangelog |
        Where-Object { $_ -match '^-\s+\S' -and $_.Length -ge 255 } |
        Select-Object -First 1
    Assert-ReleaseCondition ($null -eq $overlongEntry) (
        "Changelog entries must remain one line and shorter than 255 " +
        "characters: $publicChangelog"
    )
}
$currentDescriptionPaths = @(
    (Join-Path $releaseRoot "NEXUS_DESCRIPTION.md"),
    (Join-Path $releaseRoot "NEXUS_DESCRIPTION.bbcode.txt"),
    (Join-Path $releaseRoot "WORKSHOP_DESCRIPTION.bbcode.txt"),
    $releaseReadmePath
)
foreach ($descriptionPath in $currentDescriptionPaths) {
    $descriptionSource = Get-Content -LiteralPath $descriptionPath -Raw
    Assert-ReleaseCondition (
        $descriptionSource -notmatch
            '(?i)gamepad(?:\s+placement)?\s+controls\s+are\s+not\s+supported'
    ) "Current release copy still says gamepad controls are unsupported: $descriptionPath"
}
$darnMenuSource = Get-Content -LiteralPath $darnMenuPath -Raw
$configSource = Get-Content -LiteralPath $configPath -Raw
$gamepadSource = Get-Content -LiteralPath $gamepadPath -Raw
$runtimeSource = Get-Content -LiteralPath $runtimePath -Raw
Assert-ReleaseCondition (
    $darnMenuSource -match 'local\s+SCHEMA_VERSION\s*=\s*15'
) "DarnMenu schema constant version 15 was not found."
Assert-ReleaseCondition ($darnMenuSource -match 'schemaVersion\s*=\s*15') `
    "Embedded DarnMenu schema version 15 was not found."
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
foreach ($gamepadSetting in @(
    "gamepad_enabled",
    "gamepad_invert_forward_back",
    "gamepad_invert_height",
    "gamepad_swap_rotate_buttons"
)) {
    Assert-ReleaseCondition (
        $darnMenuSource -match [regex]::Escape($gamepadSetting)
    ) "DarnMenu gamepad setting '$gamepadSetting' was not found."
}
Assert-ReleaseCondition (
    $gamepadSource -match
        'register_hook\(C\.hook_path,\s*self\.hook_callback\)'
) "Gamepad input must use one meaningful Blueprint hook callback."
Assert-ReleaseCondition (
    $gamepadSource -match 'self\.hook_pre_id\s*=\s*pre_id' -and
    $gamepadSource -match 'self\.hook_post_id\s*=\s*post_id'
) "Gamepad input must retain both UE4SS Blueprint hook IDs."
Assert-ReleaseCondition (
    $gamepadSource -notmatch
        '\b(?:LoopAsync|LoopInGameThreadWithDelay|ExecuteWithDelay)\s*\('
) "Gamepad input must remain event-driven and free of recurring poll loops."
Assert-ReleaseCondition (
    $gamepadSource -notmatch
        '(?i)\b(?:poll_interval|polling_interval|start_poll|poll_loop)\b'
) "Gamepad input must not add a configurable or permanent polling cadence."
Assert-ReleaseCondition (
    $configSource -notmatch
        '(?i)\b(?:poll_interval|maximum_actions_per_poll)\b'
) "Gamepad configuration must not expose polling controls."
Assert-ReleaseCondition (
    $configSource -match
        'gamepad\s*=\s*\{[\s\S]*?enabled\s*=\s*true'
) "Gamepad support must default to enabled for the 0.3.0 NativeUI alpha."
Assert-ReleaseCondition (
    $gamepadSource -match
        '\[22\]\s*=\s*\{[\s\S]*?name\s*=\s*"Unfrozen_L3_DPadUp"' -and
    $gamepadSource -match
        'serial\s*=\s*"GamepadUnfrozenCopyFreezeSerial"'
) "Gamepad input must preserve enum 0-21 and append Freeze into Piece at 22."
Assert-ReleaseCondition (
    $gamepadSource -match
        'freeze_to_piece\s*=\s*"GP_UnfrozenCopyFreezeChord"'
) "The gamepad guide must configure the Freeze into Piece chord widget."
Assert-ReleaseCondition (
    $gamepadSource -notmatch 'self\.host\s*='
) "The gamepad adapter must not retain a UI UObject across map transitions."
Assert-ReleaseCondition (
    $gamepadSource -match
        '_apply_enabled\(host,\s*self\.enabled\s+and\s+self\.started\)'
) "The Blueprint gamepad bridge must stay disabled when hook registration fails."
Assert-ReleaseCondition (
    $gamepadSource -match
        'hook_registration_terminal\s*=\s*true' -and
    $gamepadSource -match
        'if\s+self\.hook_registration_terminal\s+then'
) "Incomplete gamepad hook IDs must fail closed without repeated registration."
Assert-ReleaseCondition (
    $gamepadSource -match
        'if\s+not\s+self\.enabled\s+or\s+not\s+self\.started\s+then'
) "A partial or disabled gamepad hook must never dispatch controller actions."
Assert-ReleaseCondition (
    $gamepadSource -notmatch 'function\s+Instance:refresh_config'
) "Gamepad configuration is restart-only and must not expose an unsafe live reload API."
Assert-ReleaseCondition (
    $gamepadSource -match
        'if\s+dispatched_or_error\s*==\s*false\s+then'
) "A rejected guarded dispatch must be reported instead of treated as success."

$mainSource = Get-Content -LiteralPath $mainPath -Raw
$keybindingsSource = Get-Content -LiteralPath $keybindingsPath -Raw
$companionBridgeSource = Get-Content -LiteralPath $companionBridgePath -Raw
$nativePakBuilderSource = Get-Content -LiteralPath $nativePakBuilderPath -Raw
Assert-ReleaseCondition (
    $mainSource -match 'local\s+Gamepad\s*=\s*require\("gamepad"\)' -and
    $mainSource -match 'local\s+CompanionBridge\s*=\s*require\("companion_bridge"\)' -and
    $mainSource -match 'Gamepad\.new\s*\(' -and
    $mainSource -match 'dispatch_action\s*=\s*dispatch_action'
) "main.lua must compose the event-driven gamepad adapter through its guarded dispatcher."
Assert-ReleaseCondition (
    $mainSource -match [regex]::Escape("Loaded Perfect Placement $Version")
) "The Lua startup version does not match '$Version'."
Assert-ReleaseCondition (
    $mainSource -match
        [regex]::Escape("Consolidated native UI and gamepad bridge revision 1 loaded.")
) "The Lua bridge revision does not match the consolidated NativeUI PAK."
Assert-ReleaseCondition (
    $companionBridgeSource -match [regex]::Escape('/Game/Mods/PerfectPlacement/ModActor') -and
    $companionBridgeSource -match 'RegisterLoadMapPostHook' -and
    $companionBridgeSource -match 'world:SpawnActor' -and
    $companionBridgeSource -match 'FindAllOf'
) "The companion bridge must safely reuse or spawn ModActor from the regular _P.pak."
Assert-ReleaseCondition (
    $mainSource -match 'ue_helpers\s*=\s*UEHelpers' -and
    $companionBridgeSource -match 'ue_helpers\s*=\s*options\.ue_helpers' -and
    $companionBridgeSource -notmatch '(?m)^\s*return\s+UEHelpers\.'
) "The companion bridge must receive UEHelpers explicitly instead of depending on another module's local or a missing global."
Assert-ReleaseCondition (
    $companionBridgeSource -notmatch
        '\b(?:LoopAsync|LoopInGameThreadWithDelay|ExecuteWithDelay)\s*\('
) "The companion bridge must not add a recurring polling loop."
Assert-ReleaseCondition (
    $nativePakBuilderSource -match 'CookedRuntimeDirectory' -and
    $nativePakBuilderSource -match 'ModActor\.uasset' -and
    $nativePakBuilderSource -match 'WBP_PerfectPlacement_KeyGuide\.uasset' -and
    $nativePakBuilderSource -match 'Get-ChildItem\s+-LiteralPath\s+\$cookedRuntimeRoot'
) "The NativeUI PAK builder must package the cooked companion runtime."
Assert-ReleaseCondition (
    $configSource -match 'use_native_construction_guide\s*=\s*true'
) "Native construction-guide integration must default to enabled."
Assert-ReleaseCondition (
    $gamepadSource -match
        'function\s+Instance:get_keycap_texture\(token\)[\s\S]*?' +
        'return\s+self:_load_keycap\(token\)'
) "The native guide must reuse the hardened gamepad keycap loader."
Assert-ReleaseCondition (
    $mainSource -match '"VerticalBox_PP"' -and
    $mainSource -match 'keyboard_frozen\s*=' -and
    $mainSource -match 'keyboard_unfrozen\s*=' -and
    $mainSource -match 'gamepad_frozen\s*=' -and
    $mainSource -match 'gamepad_unfrozen\s*='
) "The native guide must build and cache all four device/state panels."
Assert-ReleaseCondition (
    $mainSource -match
        'create_action_separator\s*=\s*function\([\s\S]*?' +
        '"/Script/UMG\.Border"' -and
    $mainSource -match 'box:SetWidthOverride\(1\.0\)' -and
    $mainSource -match 'box:SetHeightOverride\(22\.0\)' -and
    $mainSource -match 'divider:SetBrushColor' -and
    $mainSource -match
        'if\s+rendered_actions\s*>\s*0\s+then[\s\S]*?' +
        'create_action_separator\(construction\)'
) "Paired native-guide actions must render a separator between complete chords."
Assert-ReleaseCondition (
    $mainSource -match 'Keybindings\.get_shifted_keypad_registration\(binding\)' -and
    $mainSource -match ':WINDOWS_SHIFT_KEYPAD:' -and
    $mainSource -match 'translated_modifier_values' -and
    $keybindingsSource -match 'keys\.NUMPAD_DECIMAL\.shifted_virtual_key\s*=\s*0x2E' -and
    $keybindingsSource -match 'function\s+M\.get_shifted_keypad_registration\(binding\)'
) "Shift-modified numpad bindings must register Windows-translated navigation events without the suppressed Shift modifier."
Assert-ReleaseCondition (
    $mainSource -match [regex]::Escape(
        '/Script/Pal.PalUIBuildingModel:CanChangeReplaceModeForBuildObject'
    ) -and
    $mainSource -match
        'if state == State\.EDITING then\s*' +
        'verbose\("Blocked Replacement Mode while preview is frozen\."\)\s*' +
        'return false' -and
    $mainSource -match
        'RegisterHook\(\s*can_change_replace_path,\s*pre_callback,\s*post_callback'
) "Replacement Mode must be unavailable while the preview is frozen."
foreach ($label in @(
    "Left / Right",
    "Forward / Back",
    "Up / Down",
    "Rotate Left / Right",
    "Step Down / Up (%g cm)",
    "Reset",
    "Unfreeze",
    "Freeze",
    "Copy Piece",
    "Copy and Freeze"
)) {
    Assert-ReleaseCondition ($mainSource -match [regex]::Escape($label)) `
        "The native guide is missing '$label'."
}
Assert-ReleaseCondition (
    $mainSource -match 'local\s+keycap_size\s*=\s*36\.0' -and
    $mainSource -match 'box:SetWidthOverride\(keycap_size\)' -and
    $mainSource -match 'box:SetHeightOverride\(keycap_size\)'
) "Native keycaps must retain the square Palworld-sized constraint."
Assert-ReleaseCondition (
    $mainSource -match
        'schedule_stock_layout\s*=\s*function\([\s\S]*?' +
        'runtime\.delay\(\s*75,[\s\S]*?' +
        'queued_freeze_generation\s*~=\s*freeze_transition_generation[\s\S]*?' +
        'queued_construction_generation\s*~=\s*construction_ui_generation'
) "Native layout mutation must remain deferred, coalesced, and generation-safe."
Assert-ReleaseCondition (
    $mainSource -match 'parent:RemoveChild\(item\.widget\)' -and
    $mainSource -match 'parent:AddChildToVerticalBox\(item\.widget\)'
) "Frozen stock rows must be detached and restored as complete widgets."
Assert-ReleaseCondition (
    $mainSource -notmatch
        'RegisterHook\(\s*["'']?/Script/UMG(?:\.|/)Widget:SetVisibility'
) "The crash-prone global UMG SetVisibility hook must never be restored."
Assert-ReleaseCondition (
    $mainSource -match
        'register_action\("freeze_to_piece",\s*freeze_to_looked_at_build_piece\)'
) "The copy-and-freeze action is not registered."
Assert-ReleaseCondition (
    $mainSource -match
        'freeze_to_piece\s*=\s*\{\s*"CopyFreezeChord"\s*\}'
) "The companion guide must populate its copy-and-freeze chord widget."
Assert-ReleaseCondition (
    $mainSource -notmatch 'refresh_keycaps_for_ui_host'
) "UI-host recreation must not apply configured keycaps a second time."
Assert-ReleaseCondition (
    $mainSource -notmatch 'refresh_bindings_from_darnmenu'
) "The obsolete per-UI-host binding refresh must not be restored."
Assert-ReleaseCondition (
    $configSource -match 'ui_lifecycle_counters\s*=\s*false' -and
    $configSource -match 'ui_lifecycle_log_interval_ms\s*=\s*5000'
) "UI lifecycle counters must remain optional and disabled by default."
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
) "Both frozen-validity entry points must honor the configured validity toggle."
Assert-ReleaseCondition (
    $runtimeSource -notmatch
        'retained_callback|completed_callback|retained_history'
) "The unsafe rotating callback-retention history must not be restored."
Assert-ReleaseCondition (
    ([regex]::Matches(
        $runtimeSource,
        '\bExecuteInGameThread\s*\('
    )).Count -eq 2
) "Direct game-thread calls must remain isolated inside runtime.lua."
Assert-ReleaseCondition (
    $runtimeSource -match 'EGameThreadMethod\.EngineTick'
) "Immediate PP callbacks must use the EngineTick queue."
Assert-ReleaseCondition (
    $runtimeSource -notmatch 'EGameThreadMethod\.ProcessEvent'
) "Perfect Placement must never force work through the shared ProcessEvent queue."
Assert-ReleaseCondition (
    ($runtimeSource -match 'LoopInGameThreadAfterFrames') -and
    ($runtimeSource -match 'PauseDelayedAction') -and
    ($runtimeSource -match 'UnpauseDelayedAction')
) "Input dispatch must use a stable paused EngineTick pulse."
Assert-ReleaseCondition (
    ($runtimeSource -match 'LoopInGameThreadWithDelay') -and
    ($runtimeSource -match 'CancelDelayedAction')
) "Recurring game-thread work must use an owned, cancellable stable loop."
Assert-ReleaseCondition (
    $runtimeSource -match 'ExecuteInGameThreadWithDelay'
) "Delayed work must prefer UE4SS-owned game-thread actions."
Assert-ReleaseCondition (
    $runtimeSource -match 'ExecuteWithDelay'
) "The runtime helper must retain the legacy delayed-action fallback."
Assert-ReleaseCondition (
    $mainSource -match 'local\s+Runtime\s*=\s*require\("runtime"\)'
) "main.lua must load the centralized game-thread runtime helper."
Assert-ReleaseCondition (
    $mainSource -notmatch '\bLoopAsync\s*\('
) "main.lua must not bridge recurring async polling into EngineTick."
Assert-ReleaseCondition (
    $mainSource -notmatch
        'start_lifecycle_monitor|should_release_locked_preview|LIFECYCLE_INTERVAL_MS'
) "Frozen lifecycle handling must remain event-driven instead of polling UObjects."
Assert-ReleaseCondition (
    $mainSource -match
        'runtime\.loop\(\s*FREEZE_TO_PIECE_RETRY_MS,'
) "Copy-and-freeze readiness must reuse one owned callback."
Assert-ReleaseCondition (
    $mainSource -match
        'validity_refresh_trigger\s*=\s*runtime\.throttle\('
) "Frozen validity refresh must reuse one stable throttled callback."
Assert-ReleaseCondition (
    $mainSource -match
        'local\s+trigger\s*=\s*runtime\.pulse\('
) "Keyboard bindings must use stable, coalescing input pulses."
Assert-ReleaseCondition (
    $mainSource -match
        'type\(IsInGameThread\)\s*==\s*"function"'
) "Blueprint input must avoid redundant game-thread scheduling."
foreach ($luaPath in Get-ChildItem -LiteralPath (
    Join-Path $modRoot "Scripts"
) -Filter "*.lua") {
    if ($luaPath.Name -eq "runtime.lua") {
        continue
    }
    $luaSource = Get-Content -LiteralPath $luaPath.FullName -Raw
    Assert-ReleaseCondition (
        $luaSource -notmatch
            '\b(?:ExecuteInGameThread(?:WithDelay)?|ExecuteWithDelay)\s*\('
    ) (
        "$($luaPath.Name) bypasses runtime.lua for game-thread scheduling."
    )
}
Assert-ReleaseCondition (
    $mainSource -match 'set_actor_transform_verified'
) "Transform calls must verify success after UE4SS FHitResult marshal errors."
Assert-ReleaseCondition (
    $mainSource -notmatch 'rotation_pivot|locked_origin_pivot' -and
    $mainSource -notmatch 'GetActorBounds'
) "Frozen rotation must use Palworld's install pivot instead of a visual-bounds pivot."
Assert-ReleaseCondition (
    $mainSource -match 'preserve_preview_origin_during_rotation' -and
    $mainSource -match 'builder_component:IsSnapMode\(\)' -and
    $mainSource -match 'SnapHitBuildObjectCache' -and
    $mainSource -match 'SnapHitActorCache' -and
    $mainSource -match 'AUTOMATIC_SNAP_OFFSET_THRESHOLD_CM' -and
    $mainSource -match 'inferred_structural_snap'
) "Snapped rotation must detect explicit snap state and automatic structural snap offsets."
$rotatePreviewFunction = [regex]::Match(
    $mainSource,
    'local function rotate_preview\(' +
        '(?<body>[\s\S]*?)\r?\nend\r?\n\r?\n' +
        'local function reset_preview_transform'
)
Assert-ReleaseCondition $rotatePreviewFunction.Success `
    "The frozen preview rotation function was not found."
Assert-ReleaseCondition (
    $rotatePreviewFunction.Groups["body"].Value -match
        'if\s+preserve_preview_origin_during_rotation' -and
    $rotatePreviewFunction.Groups["body"].Value -match
        'preview_anchor_x\s*=\s*desired_location\.X' -and
    $rotatePreviewFunction.Groups["body"].Value -match
        'desired_location\.X\s*=\s*preview_anchor_x' -and
    $rotatePreviewFunction.Groups["body"].Value -match
        'desired_location\.Y\s*=\s*preview_anchor_y'
) "Snapped rotation must preserve the preview origin by compensating the install checker."
Assert-ReleaseCondition (
    $mainSource -match 'registered_keybind_callbacks'
) "Registered keybind callbacks must keep a module-lifetime Lua reference."
Assert-ReleaseCondition (
    $mainSource -notmatch 'IDLE_UI_REFRESH_TICKS|BUILDER_FALLBACK_RETRY_TICKS'
) "Normal gameplay must not retain an idle guide-poll cadence."
$stableGuideHelper = [regex]::Match(
    $mainSource,
    'local function unfrozen_guide_is_stable\(\)' +
        '(?<body>[\s\S]*?)\r?\nend\r?\n\r?\n' +
        'local function show_unfrozen_guide_for_active_preview'
)
Assert-ReleaseCondition $stableGuideHelper.Success `
    "The stable unfrozen-guide fast path was not found."
Assert-ReleaseCondition (
    $stableGuideHelper.Groups["body"].Value -match
        'if\s+unfrozen_guide_transition_is_locked\(\)' -and
    $stableGuideHelper.Groups["body"].Value -match
        'requested_mode' -and
    $stableGuideHelper.Groups["body"].Value -match
        'instance\.mode\s*==\s*requested_mode' -and
    $stableGuideHelper.Groups["body"].Value -match
        'perfect_placement_ui_mode\s*==\s*"unfrozen"' -and
    $stableGuideHelper.Groups["body"].Value -match
        'perfect_placement_ui_host\s*~=\s*nil'
) "Stable unfrozen callbacks must use the native panel fast path before companion discovery."
$companionUiUpdate = [regex]::Match(
    $mainSource,
    'local function update_perfect_placement_ui\(' +
        '(?<body>[\s\S]*?)\r?\nend\r?\n\r?\n' +
        'local function refresh_perfect_placement_ui'
)
Assert-ReleaseCondition $companionUiUpdate.Success `
    "The companion UI update function was not found."
Assert-ReleaseCondition (
    $companionUiUpdate.Groups["body"].Value -match
        'requested_mode\s*==\s*perfect_placement_ui_mode\s*' +
        'and\s+not\s+show_transition_toast\s*' +
        'and\s+is_live_companion_ui_host\(perfect_placement_ui_host\)[\s\S]*?' +
        'return\s+true' -and
    $companionUiUpdate.Groups["body"].Value -match
        'perfect_placement_ui_mode\s*=\s*requested_mode'
) "Repeated stock key-guide events must not rebuild an unchanged companion guide."
$companionUpdateBody = $companionUiUpdate.Groups["body"].Value
$sameModeGuardStart = $companionUpdateBody.IndexOf(
    'if requested_mode == perfect_placement_ui_mode'
)
$sameModeHostDiscovery = $companionUpdateBody.IndexOf(
    'local host = find_perfect_placement_ui_host()'
)
$sameModeReturnsEarly = $false
if ($sameModeGuardStart -ge 0 -and $sameModeHostDiscovery -gt $sameModeGuardStart) {
    $sameModeGuardSegment = $companionUpdateBody.Substring(
        $sameModeGuardStart,
        $sameModeHostDiscovery - $sameModeGuardStart
    )
    $sameModeReturnsEarly = $sameModeGuardSegment -match
        'then\s*return\s+true\s*end'
}
Assert-ReleaseCondition (
    $sameModeGuardStart -ge 0 -and
    $sameModeGuardStart -lt $sameModeHostDiscovery -and
    $sameModeReturnsEarly
) "The stable companion mode must return before host discovery."
$exactClassHelper = [regex]::Match(
    $mainSource,
    'local function full_name_is_live_exact_class\(' +
        '(?<body>[\s\S]*?)\r?\nend\r?\n\r?\nlocal KEYCAP_IMAGE_SLOTS'
)
Assert-ReleaseCondition $exactClassHelper.Success `
    "The exact live-object name and class helpers were not found."
Assert-ReleaseCondition (
    $exactClassHelper.Groups["body"].Value -match
        'full_name_is_available\(name\)' -and
    $exactClassHelper.Groups["body"].Value -match
        'class_name_from_full_name\(name\)\s*==\s*expected_class_name' -and
    $exactClassHelper.Groups["body"].Value -match '/Engine/Transient\.' -and
    $exactClassHelper.Groups["body"].Value -match 'Default__' -and
    $exactClassHelper.Groups["body"].Value -match
        'is_live_object_of_exact_class\([\s\S]*?' +
        'full_name_is_live_exact_class\(\s*full_name\(object\)'
) "Live UMG discovery must require an exact transient instance and reject templates."
function Test-LiveExactClassName {
    param([string]$Name, [string]$ExpectedClassName)
    $classToken = ($Name -split '\s+', 2)[0]
    return $classToken -eq $ExpectedClassName -and
        $Name.Contains('/Engine/Transient.') -and
        -not $Name.Contains('Default__')
}
$constructionClassName = 'WBP_IngameConstruction_C'
$liveConstructionName =
    'WBP_IngameConstruction_C /Engine/Transient.PalGameEngine:WBP_PlayerUI_C.WidgetTree.WBP_IngameConstruction_C_1'
$childConstructionName =
    'WBP_Ingameconstruction_KeyGuide_C /Engine/Transient.PalGameEngine:WBP_IngameConstruction_C_1.WidgetTree.KeyGuide_1'
$templateConstructionName =
    'WBP_IngameConstruction_C /Game/Pal/UI/WBP_IngameConstruction.Default__WBP_IngameConstruction_C'
Assert-ReleaseCondition (
    (Test-LiveExactClassName $liveConstructionName $constructionClassName) -and
    -not (Test-LiveExactClassName $childConstructionName $constructionClassName) -and
    -not (Test-LiveExactClassName $templateConstructionName $constructionClassName)
) "Exact construction classification must accept a nested live root and reject child and template names."
Assert-ReleaseCondition (
    $mainSource -match
        'local function full_name_is_available\(name\)[\s\S]*?' +
        'type\(name\)\s*==\s*"string"[\s\S]*?' +
        'name\s*~=\s*"<invalid>"\s+and\s+name\s*~=\s*"<name unavailable>"'
) "Lifecycle identity checks must reject every full-name sentinel."
$hostFinder = [regex]::Match(
    $mainSource,
    'local function find_perfect_placement_ui_host\(\)' +
        '(?<body>[\s\S]*?)\r?\nend\r?\n\r?\n' +
        'local function call_ui_host_function'
)
Assert-ReleaseCondition $hostFinder.Success `
    "The companion UI host finder was not found."
Assert-ReleaseCondition (
    $hostFinder.Groups["body"].Value -match
        'ui_host_setup_pending\s+or\s+ui_host_lookup_blocked[\s\S]*?' +
        'return\s+nil[\s\S]*?' +
        'live_companion_ui_host_name\(perfect_placement_ui_host\)[\s\S]*?' +
        'FindFirstOf' -and
    $hostFinder.Groups["body"].Value -match
        'preferred_name\s*=\s*preferred_ui_host_full_name[\s\S]*?' +
        'candidate_name\s*~=\s*preferred_name' -and
    $hostFinder.Groups["body"].Value -match
        'if\s+cached_host_name\s*~=\s*nil\s*' +
        'and\s*\(not\s+require_preferred\s+or\s+' +
        'cached_host_name\s*==\s*preferred_name\)\s*' +
        'then\s*return\s+perfect_placement_ui_host\s*end' -and
    $hostFinder.Groups["body"].Value -match
        'if\s+candidate_name\s*==\s*nil\s*' +
        'or\s*\(require_preferred\s+and\s+' +
        'candidate_name\s*~=\s*preferred_name\)\s*' +
        'then\s*return\s+false\s*end' -and
    $hostFinder.Groups["body"].Value -match
        'preferred_ui_host_full_name\s*=\s*host_name' -and
    $hostFinder.Groups["body"].Value -match
        'ui_host_lookup_blocked\s*=\s*true'
) "Host discovery must back off misses and prefer the latest notified live instance."
$uiHostCallback = [regex]::Match(
    $mainSource,
    'ui_host_notify_callback\s*=\s*function\([^)]*\)' +
        '(?<body>[\s\S]*?)\r?\nend\r?\n\r?\nconstruction_ui_notify_callback'
)
Assert-ReleaseCondition $uiHostCallback.Success `
    "The companion UI host callback was not found."
Assert-ReleaseCondition (
    $uiHostCallback.Groups["body"].Value -match
        'ui_host_lookup_blocked\s*=\s*false[\s\S]*?' +
        'notified_name\s*=\s*live_companion_ui_host_name\(new_object\)[\s\S]*?' +
        'preferred_ui_host_full_name\s*=\s*notified_name[\s\S]*?' +
        'perfect_placement_ui_mode\s*=\s*nil[\s\S]*?' +
        'if\s+ui_host_setup_pending\s+then[\s\S]*?' +
        'find_active_build_context\(false\)[\s\S]*?' +
        'live_frozen\s*=\s*state\s*==\s*State\.EDITING[\s\S]*?' +
        'live_unfrozen\s*=\s*is_valid\(active_component\)[\s\S]*?' +
        'construction_ui_is_active\(false\)\s*==\s*true[\s\S]*?' +
        'update_perfect_placement_ui\(\s*' +
        'live_frozen,\s*false,\s*' +
        'not\s*\(live_frozen\s+or\s+live_unfrozen\)\s*\)'
) "Companion UI creation must retain the newest host identity and remain hidden without a live preview."
Assert-ReleaseCondition (
    $uiHostCallback.Groups["body"].Value -match
        'if\s+ui_host_setup_pending\s+then\s*' +
        'count_ui_lifecycle_metric\("host_notify_coalesced"\)\s*' +
        'return\s*end'
) "Coalesced host notifications must return before scheduling another reacquisition."
$keyguideHookFunction = [regex]::Match(
    $mainSource,
    'local function ensure_keyguide_hook\(\)' +
        '(?<body>[\s\S]*?)\r?\nend\r?\n\r?\n' +
        'local function schedule_construction_setup_retry'
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
        'pre_id\s*=\s*pre_id,\s*post_id\s*=\s*post_id,\s*' +
        'complete\s*=\s*pre_id\s*~=\s*nil\s+and\s+post_id\s*~=\s*nil,' -and
    $keyguideHookFunction.Groups["body"].Value -match
        'return\s+keyguide_hook_registered\.complete\s*==\s*true'
) "The key-guide hook must retain complete and partial registrations without retrying them."
$keyguideCallbackStart = $keyguideHookFunction.Groups["body"].Value.IndexOf(
    'keyguide_hook_callback = function(context)'
)
$keyguideStableCheck = $keyguideHookFunction.Groups["body"].Value.IndexOf(
    'if unfrozen_guide_is_stable() and not native_ui_enabled then',
    $keyguideCallbackStart
)
$keyguideContextRead = $keyguideHookFunction.Groups["body"].Value.IndexOf(
    'return context:get()',
    $keyguideCallbackStart
)
$keyguideTransitionCheck = $keyguideHookFunction.Groups["body"].Value.IndexOf(
    'and unfrozen_guide_transition_is_locked()',
    $keyguideCallbackStart
)
Assert-ReleaseCondition (
    $keyguideCallbackStart -ge 0 -and
    $keyguideStableCheck -gt $keyguideCallbackStart -and
    $keyguideStableCheck -lt $keyguideContextRead -and
    $keyguideTransitionCheck -gt $keyguideStableCheck -and
    $keyguideTransitionCheck -lt $keyguideContextRead
) "Stable companion-only or transitional SetupKeyGuide callbacks must return before reading UObjects."
Assert-ReleaseCondition (
    $keyguideHookFunction.Groups["body"].Value -match
        'if\s+unfrozen_guide_is_stable\(\)\s+and\s+not\s+' +
        'native_ui_enabled\s*then\s*return\s*end' -and
    $keyguideHookFunction.Groups["body"].Value -match
        'if\s+state\s*~=\s*State\.EDITING\s*' +
        'and\s+unfrozen_guide_transition_is_locked\(\)\s*then[\s\S]*?' +
        'return\s*end\s*local\s+construction\s*=\s*context'
) "Stable companion-only and transitional SetupKeyGuide branches must stop before unwrapping context."
$setupRetryFunction = [regex]::Match(
    $mainSource,
    'local function schedule_construction_setup_retry\(' +
        '(?<body>[\s\S]*?)\r?\nend\r?\n\r?\n' +
        'local function ensure_construction_ui_hooks'
)
Assert-ReleaseCondition $setupRetryFunction.Success `
    "The construction Setup retry function was not found."
$setupRetryBody = $setupRetryFunction.Groups["body"].Value
$setupRetryFreezeComparison = $setupRetryBody.IndexOf(
    'queued_freeze_generation ~= freeze_transition_generation'
)
$setupRetryConstructionComparison = $setupRetryBody.IndexOf(
    'queued_construction_generation ~= construction_ui_generation'
)
$setupRetryShow = $setupRetryBody.IndexOf(
    'show_unfrozen_guide_for_active_preview()'
)
$setupRetryStaleGuard = $setupRetryBody.IndexOf(
    'if queued_freeze_generation ~= freeze_transition_generation'
)
$setupRetryIdentityGuard = $setupRetryBody.IndexOf(
    'if not full_name_is_available(queued_construction_name)'
)
$setupRetryStableGuard = $setupRetryBody.IndexOf(
    'if unfrozen_guide_is_stable() then'
)
$setupRetryStaleReturns = $false
if ($setupRetryStaleGuard -ge 0 -and
    $setupRetryIdentityGuard -gt $setupRetryStaleGuard) {
    $setupRetryStaleSegment = $setupRetryBody.Substring(
        $setupRetryStaleGuard,
        $setupRetryIdentityGuard - $setupRetryStaleGuard
    )
    $setupRetryStaleReturns = $setupRetryStaleSegment -match '\breturn\b'
}
$setupRetryIdentityReturns = $false
if ($setupRetryIdentityGuard -ge 0 -and
    $setupRetryStableGuard -gt $setupRetryIdentityGuard) {
    $setupRetryIdentitySegment = $setupRetryBody.Substring(
        $setupRetryIdentityGuard,
        $setupRetryStableGuard - $setupRetryIdentityGuard
    )
    $setupRetryIdentityReturns = $setupRetryIdentitySegment -match '\breturn\b'
}
Assert-ReleaseCondition (
    $setupRetryBody -match 'if\s+construction_setup_retry_pending\s+then' -and
    $setupRetryBody -match
        'queued_freeze_generation\s*=\s*freeze_transition_generation' -and
    $setupRetryBody -match
        'queued_construction_generation\s*=\s*construction_ui_generation' -and
    $setupRetryFreezeComparison -ge 0 -and
    $setupRetryFreezeComparison -lt $setupRetryShow -and
    $setupRetryConstructionComparison -ge 0 -and
    $setupRetryConstructionComparison -lt $setupRetryShow -and
    $setupRetryStaleReturns -and
    $setupRetryIdentityReturns -and
    $setupRetryBody -match
        'unfrozen_guide_transition_is_locked\(\)' -and
    $setupRetryBody -match
        'not\s+full_name_is_available\(queued_construction_name\)\s*or\s*' +
        'queued_construction_name\s*~=\s*full_name\(cached_construction_widget\)' -and
    ([regex]::Matches(
        $setupRetryBody,
        'construction_setup_retry_pending\s*=\s*false'
    )).Count -ge 3
) "Construction Setup retries must be single-flight, identity-bound, and generation-safe."
Assert-ReleaseCondition (
    $setupRetryBody -match
        'if\s+construction_setup_retry_pending\s+then[\s\S]*?' +
        'return\s+true\s*end' -and
    $setupRetryBody -match
        'if\s+queued_freeze_generation\s*~=\s*freeze_transition_generation' +
        '[\s\S]*?unfrozen_guide_transition_is_locked\(\)\s*then[\s\S]*?' +
        'return\s*end' -and
    $setupRetryBody -match
        'if\s+not\s+full_name_is_available\(queued_construction_name\)' +
        '[\s\S]*?queued_construction_name\s*~=\s*' +
        'full_name\(cached_construction_widget\)\s*then[\s\S]*?' +
        'return\s*end'
) "Every coalesced, stale, or replacement-bound Setup retry must stop before guide work."
Assert-ReleaseCondition (
    $setupRetryBody -match 'show_unfrozen_guide_for_active_preview\(\)' -and
    $setupRetryBody -notmatch
        'update_perfect_placement_ui\(\s*false,\s*false,\s*true\s*\)'
) "A delayed Setup retry must be show-only and never hide a guide or input actor."
$constructionHookFunction = [regex]::Match(
    $mainSource,
    'local function ensure_construction_ui_hooks\(\)' +
        '(?<body>[\s\S]*?)\r?\nend\r?\n\r?\n' +
        'update_construction_hotkey_guide\s*='
)
Assert-ReleaseCondition $constructionHookFunction.Success `
    "The construction lifecycle hook function was not found."
$constructionHookBody = $constructionHookFunction.Groups["body"].Value
$constructionStableCheck = $constructionHookBody.IndexOf(
    'unfrozen_guide_is_stable()'
)
$constructionTransitionCheck = $constructionHookBody.IndexOf(
    'or unfrozen_guide_transition_is_locked()'
)
$constructionContextRead = $constructionHookBody.IndexOf('return context:get()')
Assert-ReleaseCondition (
    $constructionStableCheck -ge 0 -and
    $constructionContextRead -gt $constructionStableCheck -and
    $constructionTransitionCheck -gt $constructionStableCheck -and
    $constructionTransitionCheck -lt $constructionContextRead
) "Stable or transitional construction Setup must return before reading UObjects."
Assert-ReleaseCondition (
    $constructionHookBody -match
        'if\s+unfrozen_guide_is_stable\(\)[\s\S]*?' +
        'unfrozen_guide_transition_is_locked\(\)\s*' +
        'then[\s\S]*?return\s*end\s*local\s+construction\s*=\s*context'
) "Suppressed construction Setup callbacks must stop before unwrapping context."
Assert-ReleaseCondition (
    $constructionHookFunction.Groups["body"].Value -match
        'RegisterHook\(\s*function_path,\s*callback\s*\)'
) "Construction lifecycle hooks must use one meaningful Blueprint callback."
Assert-ReleaseCondition (
    $constructionHookFunction.Groups["body"].Value -match
        'construction_ui_hooks\[function_path\]\s*=\s*\{\s*' +
        'callback\s*=\s*callback,\s*pre_id\s*=\s*pre_id,\s*' +
        'post_id\s*=\s*post_id,\s*' +
        'complete\s*=\s*pre_id\s*~=\s*nil\s+and\s+post_id\s*~=\s*nil,' -and
    $constructionHookFunction.Groups["body"].Value -match
        'return\s+existing\.complete\s*==\s*true'
) "Construction lifecycle hooks must retain complete and partial registrations."
Assert-ReleaseCondition (
    $constructionHookFunction.Groups["body"].Value -notmatch
        'not\s+hook_ok\s+or\s+pre_id\s*==\s*nil' -and
    $keyguideHookFunction.Groups["body"].Value -notmatch
        'not\s+ok\s+or\s+pre_id\s*==\s*nil'
) "Successful partial hook registrations must never be registered again."
$destructHook = [regex]::Match(
    $constructionHookFunction.Groups["body"].Value,
    'local destruct_path\s*=\s*"/Script/UMG\.UserWidget:Destruct"' +
        '(?<body>[\s\S]*?)\r?\n\s*for _, function_name'
)
Assert-ReleaseCondition $destructHook.Success `
    "The generic construction-widget Destruct hook was not found."
Assert-ReleaseCondition (
    $destructHook.Groups["body"].Value -match
        'RegisterHook\(\s*destruct_path,\s*destruct_callback\s*\)'
) "The generic widget Destruct hook must use one meaningful callback."
Assert-ReleaseCondition (
    $destructHook.Groups["body"].Value -match
        'construction_ui_hooks\[destruct_path\]\s*=\s*\{\s*' +
        'callback\s*=\s*destruct_callback,\s*' +
        'pre_id\s*=\s*pre_id,\s*post_id\s*=\s*post_id,\s*' +
        'complete\s*=\s*pre_id\s*~=\s*nil\s+and\s+post_id\s*~=\s*nil,'
) "The generic widget Destruct hook must retain complete and partial registrations."
Assert-ReleaseCondition (
    $destructHook.Groups["body"].Value -match
        'widget\s*==\s*cached_construction_widget[\s\S]*?' +
        'class_name_from_full_name\(widget_name\)[\s\S]*?' +
        '~=\s*CONSTRUCTION_WIDGET_CLASS_NAME[\s\S]*?' +
        'full_name_is_available\(cached_widget_name\)[\s\S]*?' +
        'cached_widget_name\s*==\s*widget_name[\s\S]*?' +
        'full_name_is_live_exact_class\([\s\S]*?' +
        'CONSTRUCTION_WIDGET_CLASS_NAME[\s\S]*?' +
        'update_perfect_placement_ui\(\s*false,\s*false,\s*true\s*\)'
) "Widget teardown must require cached identity or an exact live construction class."
Assert-ReleaseCondition (
    $destructHook.Groups["body"].Value -match
        'if\s+full_name_is_available\(cached_widget_name\)\s*then\s*' +
        'is_construction_widget\s*=\s*' +
        'cached_widget_name\s*==\s*widget_name\s*else\s*' +
        'is_construction_widget\s*=\s*' +
        'full_name_is_live_exact_class\([\s\S]*?' +
        'CONSTRUCTION_WIDGET_CLASS_NAME[\s\S]*?\)\s*end'
) "A cached construction identity must take precedence over the exact-class fallback."
$destructBody = $destructHook.Groups["body"].Value
$destructIdentityCheck = $destructBody.IndexOf(
    'widget == cached_construction_widget'
)
$destructWidgetNameRead = $destructBody.IndexOf('full_name(widget)')
$destructClassCheck = $destructBody.IndexOf(
    'class_name_from_full_name(widget_name)'
)
$destructCachedNameRead = $destructBody.IndexOf(
    'full_name(cached_construction_widget)'
)
$destructClassRejectsEarly = $false
if ($destructClassCheck -ge 0 -and $destructCachedNameRead -gt $destructClassCheck) {
    $destructClassRejectSegment = $destructBody.Substring(
        $destructClassCheck,
        $destructCachedNameRead - $destructClassCheck
    )
    $destructClassRejectsEarly = $destructClassRejectSegment -match '\breturn\b'
}
Assert-ReleaseCondition (
    $destructIdentityCheck -ge 0 -and
    $destructIdentityCheck -lt $destructWidgetNameRead -and
    $destructWidgetNameRead -lt $destructClassCheck -and
    $destructClassCheck -lt $destructCachedNameRead -and
    $destructClassRejectsEarly -and
    $destructBody -match
        'if\s+ui_lifecycle_metrics_enabled[\s\S]*?' +
        'string\.find\([\s\S]*?CONSTRUCTION_WIDGET_CLASS_NAME' -and
    $destructBody -match
        'count_ui_lifecycle_metric\([\s\S]*?' +
        '"construction_child_destruct"[\s\S]*?' +
        'end\s*return\s*end\s*local\s+cached_widget_name'
) "Global widget teardown must reject unrelated classes before cached-name work or diagnostics."
Assert-ReleaseCondition (
    $destructHook.Groups["body"].Value -notmatch
        'is_construction_widget\s*=\s*string\.find'
) "Child outer paths must never classify a widget as the construction root."
Assert-ReleaseCondition (
    $destructHook.Groups["body"].Value -notmatch 'release_preview\s*\('
) "The generic widget Destruct hook must not release a preview while stock UMG rows are dying."
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
        'local function refresh_overlap_component'
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
    $constructionUiFunction.Groups["body"].Value -match
        'is_live_object_of_exact_class\([\s\S]*?' +
        'CONSTRUCTION_WIDGET_CLASS_NAME'
) "Construction fallback scans must reject CDO and cooked WidgetTree templates."
Assert-ReleaseCondition (
    $mainSource -notmatch
        'construction_ui_scan_context_name|locked_construction_ui_was_active|' +
        'building_mode_exit_checks|locked_preview_name'
) "The retired frozen lifecycle polling state must not be restored."
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
$constructionNotifyCallback = [regex]::Match(
    $mainSource,
    'construction_ui_notify_callback\s*=\s*function\([^)]*\)' +
        '(?<body>[\s\S]*?)\r?\nend\r?\n\r?\ndo'
)
Assert-ReleaseCondition $constructionNotifyCallback.Success `
    "The construction UI notification callback was not found."
Assert-ReleaseCondition (
    $constructionNotifyCallback.Groups["body"].Value -match
        'is_live_object_of_exact_class\([\s\S]*?' +
        'CONSTRUCTION_WIDGET_CLASS_NAME' -and
    $constructionNotifyCallback.Groups["body"].Value -match
        'ensure_keyguide_hook\(\)[\s\S]*?ensure_construction_ui_hooks\(\)' -and
    $constructionNotifyCallback.Groups["body"].Value -match
        'if\s+not\s+is_live_companion_ui_host\(' +
        'perfect_placement_ui_host\)[\s\S]*?' +
        'preferred_ui_host_full_name\s*=\s*nil[\s\S]*?' +
        'ui_host_notify_callback\(\)'
) "Construction creation must cache a live root, preserve a valid host, and clear stale host identity before fallback discovery."
$requiredSources = @(
    "enabled.txt",
    "Info.json",
    "README.md",
    "Scripts\config.lua",
    "Scripts\darnmenu.lua",
    "Scripts\gamepad.lua",
    "Scripts\companion_bridge.lua",
    "Scripts\keybindings.lua",
    "Scripts\main.lua",
    "Scripts\runtime.lua"
)
foreach ($relativePath in $requiredSources) {
    $sourcePath = Join-Path $modRoot $relativePath
    Assert-ReleaseCondition (Test-Path -LiteralPath $sourcePath -PathType Leaf) `
        "Missing release source: $sourcePath"
}
$expectedNativePakHash = (
    (Get-Content -LiteralPath $nativePakHashPath -Raw).Trim() -split "\s+"
)[0].ToUpperInvariant()
Assert-ReleaseCondition (
    (Get-Sha256 $nativePakPath) -eq $expectedNativePakHash
) "Native UI PAK does not match its pinned SHA-256."
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
foreach ($scriptName in @(
    "main.lua",
    "config.lua",
    "gamepad.lua",
    "companion_bridge.lua",
    "keybindings.lua",
    "runtime.lua",
    "darnmenu.lua"
)) {
    $sourceScript = Join-Path $modRoot "Scripts\$scriptName"
    $workshopScript = Join-Path $WorkshopPath "Scripts\$scriptName"
    Assert-ReleaseCondition (
        Test-Path -LiteralPath $workshopScript -PathType Leaf
    ) "Workshop package is missing Scripts\$scriptName."
    Assert-ReleaseCondition (
        (Get-Sha256 $sourceScript) -eq (Get-Sha256 $workshopScript)
    ) "Workshop package contains stale Scripts\$scriptName."
}
Assert-ReleaseCondition (
    -not (Test-Path -LiteralPath (Join-Path $WorkshopPath "LogicMods"))
) "Workshop package must not contain the retired LogicMods payload."
$workshopNativePak = Join-Path $WorkshopPath "Paks\PerfectPlacement_NativeUI_P.pak"
Assert-ReleaseCondition (
    Test-Path -LiteralPath $workshopNativePak -PathType Leaf
) "Workshop package is missing Paks\PerfectPlacement_NativeUI_P.pak."
Assert-ReleaseCondition (
    (Get-Sha256 $nativePakPath) -eq (Get-Sha256 $workshopNativePak)
) "Workshop package contains a stale or unexpected native UI PAK."
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
foreach ($scriptPath in @($nativeScaffoldBuilderPath, $nativePakBuilderPath)) {
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile(
        $scriptPath,
        [ref]$tokens,
        [ref]$errors
    ) | Out-Null
    Assert-ReleaseCondition ($errors.Count -eq 0) `
        "PowerShell syntax error in $($scriptPath): $($errors[0].Message)"
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

$luaCompiler = $null
foreach ($candidate in @("luac5.4", "luac54", "luac")) {
    $luaCompiler = Get-Command $candidate -ErrorAction SilentlyContinue
    if ($luaCompiler) {
        break
    }
}
if ($luaCompiler) {
    $luaCompilerVersion = (& $luaCompiler.Source -v 2>&1 | Out-String).Trim()
    Assert-ReleaseCondition (
        $luaCompilerVersion -match 'Lua 5\.4(?:\.\d+)?'
    ) (
        "Lua 5.4 compiler required; '$($luaCompiler.Source)' reported " +
        "'$luaCompilerVersion'."
    )
    foreach ($luaPath in Get-ChildItem -LiteralPath (Join-Path $modRoot "Scripts") -Filter "*.lua") {
        & $luaCompiler.Source -p $luaPath.FullName
        Assert-ReleaseCondition ($LASTEXITCODE -eq 0) `
            "Lua syntax validation failed: $($luaPath.FullName)"
    }
    & $luaCompiler.Source -p $runtimeTestPath
    Assert-ReleaseCondition ($LASTEXITCODE -eq 0) `
        "Lua syntax validation failed: $runtimeTestPath"
} elseif ($RequireLuaCompiler) {
    throw "Lua 5.4 luac is required but was not found on PATH."
} else {
    Write-Warning "Lua 5.4 luac was not found; complete the Lua syntax item in PRE_DEPLOY_CHECKLIST.md."
}

$luaRuntimePath = $null
if ($luaCompiler) {
    $siblingRuntimePath = Join-Path (
        Split-Path -Parent $luaCompiler.Source
    ) "lua.exe"
    if (Test-Path -LiteralPath $siblingRuntimePath -PathType Leaf) {
        $luaRuntimePath = $siblingRuntimePath
    }
}
if (-not $luaRuntimePath) {
    foreach ($candidate in @("lua5.4", "lua54", "lua")) {
        $luaRuntime = Get-Command $candidate -ErrorAction SilentlyContinue
        if ($luaRuntime) {
            $luaRuntimePath = $luaRuntime.Source
            break
        }
    }
}
if ($luaRuntimePath) {
    $luaRuntimeVersion = (
        & $luaRuntimePath -e "io.write(_VERSION)" 2>&1 |
            Out-String
    ).Trim()
    Assert-ReleaseCondition ($LASTEXITCODE -eq 0) (
        "Could not execute the Lua runtime at '$luaRuntimePath'."
    )
    Assert-ReleaseCondition ($luaRuntimeVersion -eq "Lua 5.4") (
        "Lua 5.4 runtime required; '$luaRuntimePath' reported " +
        "'$luaRuntimeVersion'."
    )
    & $luaRuntimePath $runtimeTestPath $repoRoot
    Assert-ReleaseCondition ($LASTEXITCODE -eq 0) `
        "Perfect Placement runtime regression tests failed."
} elseif ($RequireLuaCompiler) {
    throw (
        "A Lua 5.4 interpreter is required for the runtime regression tests. " +
        "Place lua.exe beside luac.exe or add lua5.4, lua54, or lua to PATH."
    )
} else {
    Write-Warning (
        "Lua 5.4 was not found; the runtime regression harness was not run."
    )
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

    Assert-ReleaseCondition (
        -not (Test-Path -LiteralPath (
            Join-Path $temporaryRoot "Pal\Content\Paks\LogicMods"
        ))
    ) "Archive must not contain the retired LogicMods payload."
    $archiveNativePak = Join-Path $temporaryRoot (
        "Pal\Content\Paks\~mods\PerfectPlacement_NativeUI_P.pak"
    )
    Assert-ReleaseCondition (
        Test-Path -LiteralPath $archiveNativePak -PathType Leaf
    ) "Archive is missing PerfectPlacement_NativeUI_P.pak."
    Assert-ReleaseCondition (
        (Get-Sha256 $nativePakPath) -eq (Get-Sha256 $archiveNativePak)
    ) "Archive contains a stale or unexpected native UI PAK."

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

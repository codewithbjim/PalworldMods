[CmdletBinding()]
param(
    [string]$Version = "0.2.0",
    [string]$WorkshopVersion = "0.2.0",
    [string]$ZipPath,
    [string]$PakSource,
    [string]$WorkshopPath,
    [switch]$RequireLuaCompiler
)

$ErrorActionPreference = "Stop"
$releaseRoot = $PSScriptRoot
$repoRoot = Split-Path -Parent (Split-Path -Parent $releaseRoot)
$modRoot = Join-Path $repoRoot "QuickConnectManager"
$scriptNames = @("config.lua", "connections.lua", "discovery.lua", "launch_ui.lua", "main.lua", "servers.lua")
$publicAuthor = "virtualbj$([char]0x00F6)rn"
if (-not $ZipPath) {
    $ZipPath = Join-Path $releaseRoot "Dist\QuickConnectManager-$Version.zip"
}
if (-not $PakSource) {
    $PakSource = Join-Path $releaseRoot "Assets\QuickConnectManager_UI_P.pak"
}
if (-not $WorkshopPath) {
    $WorkshopPath = Join-Path $releaseRoot "Dist\Workshop-$WorkshopVersion"
}

function Assert-Condition {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) {
        throw $Message
    }
}

function Get-StreamSha256 {
    param([System.IO.Stream]$Stream)
    $algorithm = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($algorithm.ComputeHash($Stream))).Replace("-", "")
    } finally {
        $algorithm.Dispose()
    }
}

$manifestPath = Join-Path $modRoot "Info.json"
$thumbnailPath = Join-Path $releaseRoot "thumbnail.png"
$nexusImagePath = Join-Path $releaseRoot "NEXUS_IMAGE.png"
$pakHashPath = Join-Path $releaseRoot "Assets\QuickConnectManager_UI_P.pak.sha256"
$requiredReleaseText = @(
    "README.txt",
    "CHANGELOG.md",
    "NEXUS_DESCRIPTION.md",
    "NEXUS_DESCRIPTION.bbcode.txt",
    "NEXUS_VERSION_CHANGELOG.txt",
    "WORKSHOP_DESCRIPTION.bbcode.txt",
    "WORKSHOP_CHANGELOG.txt",
    "PRE_DEPLOY_CHECKLIST.md"
)
foreach ($required in @($manifestPath, $thumbnailPath, $nexusImagePath, $PakSource, $pakHashPath)) {
    Assert-Condition (Test-Path -LiteralPath $required -PathType Leaf) "Missing release input: $required"
}
foreach ($name in $requiredReleaseText) {
    $required = Join-Path $releaseRoot $name
    Assert-Condition (Test-Path -LiteralPath $required -PathType Leaf) "Missing release text: $required"
}
foreach ($scriptName in $scriptNames) {
    $required = Join-Path $modRoot "Scripts\$scriptName"
    Assert-Condition (Test-Path -LiteralPath $required -PathType Leaf) "Missing runtime script: $required"
}

$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-Condition ($manifest.PackageName -eq "QuickConnectManager") "Unexpected package name '$($manifest.PackageName)'."
Assert-Condition ($manifest.Version -eq $Version) "Manifest version '$($manifest.Version)' does not match '$Version'."
Assert-Condition ($manifest.Author -eq $publicAuthor) "Manifest author must use the configured public identity."
Assert-Condition ($manifest.Thumbnail -eq "thumbnail.png") "Manifest thumbnail must be thumbnail.png."
Assert-Condition (@($manifest.Dependencies).Count -eq 1) "Manifest must have exactly one dependency."
Assert-Condition ($manifest.Dependencies[0] -eq "UE4SSExperimentalPW") "Manifest dependency must be UE4SSExperimentalPW."
Assert-Condition (@($manifest.Tags | Where-Object { $_ -notin @("UE4SS", "Utilities", "User Interface") }).Count -eq 0) "Manifest contains an unsupported Workshop tag."
$luaRule = @($manifest.InstallRule | Where-Object Type -eq "Lua")
$pakRule = @($manifest.InstallRule | Where-Object Type -eq "Paks")
Assert-Condition ($luaRule.Count -eq 1 -and $luaRule[0].Targets.Count -eq 1 -and $luaRule[0].Targets[0] -eq "./Scripts") "Lua InstallRule is invalid."
Assert-Condition ($pakRule.Count -eq 1 -and $pakRule[0].Targets.Count -eq 1 -and $pakRule[0].Targets[0] -eq "./Paks/") "Paks InstallRule is invalid."
Assert-Condition ((Get-Item -LiteralPath $thumbnailPath).Length -lt 1MB) "Thumbnail must be smaller than 1 MB."
Assert-Condition ((Get-Item -LiteralPath $nexusImagePath).Length -gt (Get-Item -LiteralPath $thumbnailPath).Length) "Nexus gallery image must preserve the full-resolution source."

$expectedPakHash = ((Get-Content -LiteralPath $pakHashPath -Raw).Trim() -split "\s+")[0].ToUpperInvariant()
$actualPakHash = (Get-FileHash -LiteralPath $PakSource -Algorithm SHA256).Hash
Assert-Condition ($actualPakHash -eq $expectedPakHash) "Release PAK hash does not match its checksum file."

$configSource = Get-Content -LiteralPath (Join-Path $modRoot "Scripts\config.lua") -Raw
$configServerBlock = [regex]::Match(
    $configSource,
    '(?s)-- QUICKCONNECT_SERVERS_BEGIN(.*?)-- QUICKCONNECT_SERVERS_END'
).Groups[1].Value
Assert-Condition (-not [string]::IsNullOrWhiteSpace($configServerBlock)) "Default release config is missing its managed server block."
Assert-Condition ($configServerBlock -notmatch 'enabled\s*=\s*true') "Default release config must not enable a fixture server."
Assert-Condition ($configServerBlock -notmatch 'password\s*=\s*"[^"\r\n]+"') "Default release config must not contain a password."

$launchSource = Get-Content -LiteralPath (Join-Path $modRoot "Scripts\launch_ui.lua") -Raw
$connectionsSource = Get-Content -LiteralPath (Join-Path $modRoot "Scripts\connections.lua") -Raw
$discoverySource = Get-Content -LiteralPath (Join-Path $modRoot "Scripts\discovery.lua") -Raw
$mainSource = Get-Content -LiteralPath (Join-Path $modRoot "Scripts\main.lua") -Raw
$serversSource = Get-Content -LiteralPath (Join-Path $modRoot "Scripts\servers.lua") -Raw
foreach ($requiredPattern in @(
    'Duplicate launch panel start request ignored',
    'local function lifecycle_step',
    'GAMEPLAY_POLL_MS',
    'discard_unattached_panel',
    'protected_call',
    'schedule_on_game_thread',
    'state.ready = options.ready ~= false',
    'title_context_revision',
    'panel_revision',
    'refresh_feedback_revision',
    'schedule_on_game_thread(1500, "Title world adoption"'
)) {
    Assert-Condition ($launchSource -match [regex]::Escape($requiredPattern)) "Missing launch hardening marker: $requiredPattern"
}
Assert-Condition ($discoverySource -match 'pcall\(loadfile,\s*path,\s*"t",\s*\{\}\)') "Discovery cache must load in an empty environment."
Assert-Condition ($discoverySource -match 'run_request_on_game_thread') "Discovery callbacks must be game-thread guarded."
Assert-Condition ($discoverySource -match 'CachedServerDisplayInfo' -and $discoverySource -match 'cached:Empty\(\)') "Refresh must clear construction-time server rows."
Assert-Condition ($discoverySource -match 'widget:RequestGetServerListBP\(') "Refresh must use Palworld's History-page query wrapper."
Assert-Condition ($discoverySource -match 'request_phase\s*=\s*"settling"') "Refresh must ignore the widget's automatic construction completion."
Assert-Condition ($discoverySource -match 'embedded_host') "Refresh must normalize History addresses that already contain a port."
Assert-Condition ($discoverySource -match 'rejections\.other_type') "Refresh must retain live enriched rows whose underlying list type is not History."
Assert-Condition ($discoverySource -match 'WBP_Title_WorldSelect_ListContent_C') "Refresh must reuse Palworld's stock dedicated-server row."
Assert-Condition ($discoverySource -match 'local function start_stock_row_pings') "Refresh must replace query latency with stock row pings."
Assert-Condition ($discoverySource -match 'row_widget:SetupByServerDisplayData\(display_data\)') "Refresh must enter Palworld's stock server-row setup flow."
Assert-Condition ($discoverySource -match 'AddPingResultCache' -and $discoverySource -match '\s-1\s*\)') "Refresh must invalidate Palworld's ping cache before stock row setup."
Assert-Condition ($discoverySource -match 'PING_TIMEOUT_MS\s*=\s*3000') "Stock server-row ping operations must retain their bounded timeout."
Assert-Condition ($discoverySource -match 'values=%s') "Stock server-row ping completion must report the actual returned values."
Assert-Condition ($discoverySource -match 'GetGameInstanceSubsystem\(controller,\s*subsystem_class\)') "Ping cache access must prefer the current title GameInstance subsystem."
Assert-Condition ($discoverySource -match 'MAX_CACHE_BYTES\s*=\s*262144' -and $discoverySource -match 'cache_path\s*\.\.\s*"\.previous"') "Discovery cache loading must be bounded and recover its previous file."
Assert-Condition ($discoverySource -match 'retain_one_shot') "Discovery must retain delayed callback references."
Assert-Condition ($launchSource -match 'retain_one_shot') "Launch UI must retain delayed callback references."
Assert-Condition ($launchSource -match 'REFRESH_ICON_SIZE\s*=\s*40') "Refresh icon must retain its doubled release size."
Assert-Condition ($launchSource -match 'LOCK_ICON_SIZE\s*=\s*27') "Lock icon must retain its 27-pixel release size."
Assert-Condition ($launchSource -match 'ADD_ICON_SIZE\s*=\s*14') "Add icon must use its reduced 14-pixel size."
Assert-Condition ($launchSource -match 'REMOVE_ICON_SIZE\s*=\s*27') "Removal icon must use its reduced 27-pixel size."
Assert-Condition ($launchSource -match 'T_prt_add_plus') "Launch UI must use the approved Add texture."
Assert-Condition ($launchSource -match 'T_icon_Guild_Edit') "Launch UI must use the approved Modify texture."
Assert-Condition ($launchSource -match 'T_icon_garbage') "Launch UI must use the approved Delete texture."
Assert-Condition ($launchSource -match 'PalEditableTextBox') "Launch editor must use Palworld-native text entry."
Assert-Condition ($launchSource -match 'PalEditableTextBox_IP' -and $launchSource -match 'PalEditableTextBox_111') "Launch editor must inherit Palworld's native address and password field archetypes."
Assert-Condition ($launchSource -match 'CircularThrobber' -and $launchSource -match 'function LaunchUI\.set_statuses') "Status refresh must use native-style per-row ping loading without rebuilding the server list."
Assert-Condition ($launchSource -match 'Gamepad_DPad_Down' -and $launchSource -match 'Gamepad_FaceButton_Right') "Launch editor must retain gamepad navigation and cancel routing."
Assert-Condition ($launchSource -match 'construct\("/Script/UMG\.ScrollBox"') "Launch server rows must use a vertical ScrollBox."
Assert-Condition ($launchSource -match 'for index = 1, #state\.entries do') "Launch server rows must render every configured entry."
Assert-Condition ($launchSource -notmatch 'math\.min\(#state\.entries, MAX_ROWS\)') "Launch server rows must not be capped at the viewport size."
Assert-Condition ($discoverySource -match 'GetDisplayVersion') "History filtering must compare against Palworld's current display version."
Assert-Condition ($discoverySource -match 'exact_version_required\s*=\s*not ping_valid or not players_valid') "Incomplete History status must require an exact client version."
Assert-Condition ($discoverySource -match 'server_version\[4\]\s*==\s*player_version\[4\]') "Exact History compatibility must compare the final build number."
Assert-Condition ($mainSource -match 'already_on_game_thread\s*==\s*true') "Launch-panel connections must use their existing UMG game thread."
Assert-Condition ($mainSource -match 'refresh_active' -and $mainSource -match 'Ignored a connect request while server status was refreshing') "Connections must be interlocked against an active native refresh."
Assert-Condition ($mainSource -match 'status_by_world_guid') "Status refresh must fall back to world-GUID reconciliation."
Assert-Condition ($mainSource -match 'startup_refresh_needed' -and $mainSource -match 'start_discovery\("startup-refresh"\)') "The initial panel must wait for a startup status refresh."
Assert-Condition ($discoverySource -match 'temporary_path\s*=\s*cache_path\s*\.\.\s*"\.tmp"') "Discovery cache must use a temporary replacement."
Assert-Condition ($serversSource -match 'local function replace_file') "Config writes must use the recoverable replacement helper."
Assert-Condition ($serversSource -match 'MAX_NAME_BYTES\s*=\s*128') "Server display names must remain bounded."
Assert-Condition ($serversSource -match 'function Servers\.unique_name') "Manual Add must retain deterministic unique-name generation."
Assert-Condition ($connectionsSource -match 'PalUIJoinGameBase:ConnectServerByAddress') "Connection tracking must observe Palworld's native join path."
Assert-Condition ($connectionsSource -match 'state\.was_title and not is_title') "Connection tracking must wait for a title-to-gameplay transition."

$nexusChangelog = (Get-Content -LiteralPath (Join-Path $releaseRoot "NEXUS_VERSION_CHANGELOG.txt") -Raw).TrimEnd("`r", "`n") -replace "`r`n", "`n"
Assert-Condition (-not [string]::IsNullOrWhiteSpace($nexusChangelog)) "Nexus version changelog is empty."
Assert-Condition ($nexusChangelog.Length -le 255) "Nexus version changelog exceeds 255 characters."
Assert-Condition ($nexusChangelog -notmatch '(?m)^\s*(?:[-*#]|\d+[.)])\s*') "Nexus version changelog must use plain lines without bullets."
$firstChangelogVersion = [regex]::Match((Get-Content -LiteralPath (Join-Path $releaseRoot "CHANGELOG.md") -Raw), '(?m)^##\s+([^\s]+)').Groups[1].Value
Assert-Condition ($firstChangelogVersion -eq $Version) "CHANGELOG.md does not begin with $Version."
$firstWorkshopLine = Get-Content -LiteralPath (Join-Path $releaseRoot "WORKSHOP_CHANGELOG.txt") | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1
Assert-Condition ($firstWorkshopLine -match [regex]::Escape($WorkshopVersion)) "Workshop changelog does not begin with $WorkshopVersion."
foreach ($publicChangelog in @((Join-Path $releaseRoot "CHANGELOG.md"), (Join-Path $releaseRoot "WORKSHOP_CHANGELOG.txt"))) {
    $overlongEntry = Get-Content -LiteralPath $publicChangelog | Where-Object { $_ -match '^[-*]\s+\S' -and $_.Length -ge 255 } | Select-Object -First 1
    Assert-Condition ($null -eq $overlongEntry) "Changelog list entries must remain shorter than 255 characters: $publicChangelog"
}

if ($RequireLuaCompiler) {
    $luac = Get-Command luac -ErrorAction SilentlyContinue
    Assert-Condition ($null -ne $luac) "Lua compiler was required but luac was not found."
    foreach ($scriptName in $scriptNames) {
        & $luac.Source -p (Join-Path $modRoot "Scripts\$scriptName")
        if ($LASTEXITCODE -ne 0) {
            throw "Lua syntax validation failed for $scriptName."
        }
    }
}

Assert-Condition (Test-Path -LiteralPath $ZipPath -PathType Leaf) "Release archive not found: $ZipPath"
Add-Type -AssemblyName System.IO.Compression.FileSystem
$sourceByEntry = @{
    "README.txt" = Join-Path $releaseRoot "README.txt"
    "CHANGELOG.md" = Join-Path $releaseRoot "CHANGELOG.md"
    "Pal/Binaries/Win64/UE4SS/Mods/QuickConnectManager/enabled.txt" = Join-Path $modRoot "enabled.txt"
    "Pal/Binaries/Win64/UE4SS/Mods/QuickConnectManager/Info.json" = $manifestPath
    "Pal/Binaries/Win64/UE4SS/Mods/QuickConnectManager/README.md" = Join-Path $modRoot "README.md"
    "Pal/Binaries/Win64/UE4SS/Mods/QuickConnectManager/thumbnail.png" = $thumbnailPath
    "Pal/Content/Paks/~mods/QuickConnectManager_UI_P.pak" = $PakSource
}
foreach ($scriptName in $scriptNames) {
    $sourceByEntry["Pal/Binaries/Win64/UE4SS/Mods/QuickConnectManager/Scripts/$scriptName"] = Join-Path $modRoot "Scripts\$scriptName"
}
$archive = [System.IO.Compression.ZipFile]::OpenRead([System.IO.Path]::GetFullPath($ZipPath))
try {
    $leafEntries = @($archive.Entries | Where-Object {
        -not ($_.FullName.EndsWith("/") -or $_.FullName.EndsWith("\"))
    })
    Assert-Condition ($leafEntries.Count -eq $sourceByEntry.Count) "Release archive contains unexpected or missing files."
    foreach ($entryName in $sourceByEntry.Keys) {
        $entry = $leafEntries | Where-Object {
            $_.FullName.Replace("\", "/") -eq $entryName
        } | Select-Object -First 1
        Assert-Condition ($null -ne $entry) "Release archive is missing $entryName."
        $stream = $entry.Open()
        try {
            $archiveHash = Get-StreamSha256 $stream
        } finally {
            $stream.Dispose()
        }
        $sourceHash = (Get-FileHash -LiteralPath $sourceByEntry[$entryName] -Algorithm SHA256).Hash
        Assert-Condition ($archiveHash -eq $sourceHash) "Archive payload hash mismatch: $entryName"
    }
    $unsafeEntry = $leafEntries | Where-Object { $_.FullName.Replace("\", "/") -match '(?i)(discovery_cache|\.bak$|\.tmp$|\.previous$|/tests?/)' } | Select-Object -First 1
    Assert-Condition ($null -eq $unsafeEntry) "Archive contains a local cache, backup, temporary file, or test fixture."
} finally {
    $archive.Dispose()
}

Assert-Condition (Test-Path -LiteralPath $WorkshopPath -PathType Container) "Workshop package not found: $WorkshopPath"
$workshopManifestPath = Join-Path $WorkshopPath "Info.json"
Assert-Condition (Test-Path -LiteralPath $workshopManifestPath -PathType Leaf) "Workshop package is missing Info.json."
$workshopManifest = Get-Content -LiteralPath $workshopManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-Condition ($workshopManifest.PackageName -eq "QuickConnectManager") "Workshop manifest package name is invalid."
Assert-Condition ($workshopManifest.Version -eq $WorkshopVersion) "Workshop manifest version '$($workshopManifest.Version)' does not match '$WorkshopVersion'."
$sourceManifestText = [System.IO.File]::ReadAllText($manifestPath)
$versionPattern = '(?m)^(\s*"Version"\s*:\s*")[^"]+("\s*,\s*)$'
$expectedWorkshopManifestText = [regex]::Replace(
    $sourceManifestText,
    $versionPattern,
    { param($match) $match.Groups[1].Value + $WorkshopVersion + $match.Groups[2].Value },
    1
)
$actualWorkshopManifestText = [System.IO.File]::ReadAllText($workshopManifestPath)
Assert-Condition ($actualWorkshopManifestText -eq $expectedWorkshopManifestText) "Workshop manifest differs from the source by more than its channel-specific version."
$workshopSourceByPath = @{
    "thumbnail.png" = $thumbnailPath
    "Paks\QuickConnectManager_UI_P.pak" = $PakSource
}
foreach ($scriptName in $scriptNames) {
    $workshopSourceByPath["Scripts\$scriptName"] = Join-Path $modRoot "Scripts\$scriptName"
}
foreach ($relativePath in $workshopSourceByPath.Keys) {
    $staged = Join-Path $WorkshopPath $relativePath
    Assert-Condition (Test-Path -LiteralPath $staged -PathType Leaf) "Workshop package is missing $relativePath."
    Assert-Condition ((Get-FileHash -LiteralPath $staged -Algorithm SHA256).Hash -eq (Get-FileHash -LiteralPath $workshopSourceByPath[$relativePath] -Algorithm SHA256).Hash) "Workshop payload hash mismatch: $relativePath"
}
$unsafeWorkshopFile = Get-ChildItem -LiteralPath $WorkshopPath -Recurse -File | Where-Object { $_.Name -match '(?i)discovery_cache|\.bak$|\.tmp$|\.previous$' } | Select-Object -First 1
Assert-Condition ($null -eq $unsafeWorkshopFile) "Workshop package contains a local cache, backup, or temporary file."

$publicFiles = @(
    $manifestPath,
    (Join-Path $modRoot "README.md"),
    (Join-Path $releaseRoot "README.txt"),
    (Join-Path $releaseRoot "CHANGELOG.md"),
    (Join-Path $releaseRoot "NEXUS_DESCRIPTION.md"),
    (Join-Path $releaseRoot "NEXUS_DESCRIPTION.bbcode.txt"),
    (Join-Path $releaseRoot "WORKSHOP_DESCRIPTION.bbcode.txt")
)
foreach ($publicFile in $publicFiles) {
    $source = Get-Content -LiteralPath $publicFile -Raw -Encoding UTF8
    Assert-Condition ($source -notmatch '(?i)[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}') "Public file contains an email address: $publicFile"
}

Write-Host "Quick Connect Manager Nexus $Version / Workshop $WorkshopVersion release gate passed."
Write-Host "Archive SHA-256: $((Get-FileHash -LiteralPath $ZipPath -Algorithm SHA256).Hash)"

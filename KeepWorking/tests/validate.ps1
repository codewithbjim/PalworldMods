$ErrorActionPreference = 'Stop'

$modRoot = Split-Path -Parent $PSScriptRoot
$infoPath = Join-Path $modRoot 'Info.json'
$mainPath = Join-Path $modRoot 'Scripts\main.lua'
$nativePath = Join-Path $modRoot 'Native\pal_focus.c'
$helperPath = Join-Path $modRoot 'Scripts\AltTabWorkContinuationFocus.dll'
$enabledPath = Join-Path $modRoot 'enabled.txt'
$licensePath = Join-Path $modRoot 'LICENSE'

foreach ($path in @(
    $infoPath,
    $mainPath,
    $nativePath,
    $helperPath,
    $enabledPath,
    $licensePath
)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing required file: $path"
    }
}

$info = Get-Content -Raw -Encoding UTF8 -LiteralPath $infoPath | ConvertFrom-Json
if ($info.PackageName -ne 'KeepWorking') { throw 'Unexpected package name.' }
$expectedAuthor = 'virtualbj' + [char]0x00F6 + 'rn'
if ($info.Author -ne $expectedAuthor) { throw 'Unexpected author.' }
if ($info.Version -ne '0.1.0') { throw 'Unexpected version.' }
if ((Get-Content -Raw -Encoding UTF8 -LiteralPath $enabledPath).Trim() -ne '1') {
    throw 'Mod enablement marker is invalid.'
}

$main = Get-Content -Raw -Encoding UTF8 -LiteralPath $mainPath
$native = Get-Content -Raw -Encoding UTF8 -LiteralPath $nativePath
$license = Get-Content -Raw -Encoding UTF8 -LiteralPath $licensePath

foreach ($required in @(
    '/Script/Pal.PalInteractComponent:EndTriggerInteract',
    '/Script/Pal.PalNetworkWorkProgressComponent:ReceiveStartPlayerWork_ToRequestClient',
    'EXPECTED_GAME_BUILD = "24181527"',
    'EXPECTED_HELPER_SUFFIX = "\\keepworking\\scripts\\alttabworkcontinuationfocus.dll"',
    'loadNativeExport("pal_focus_is_f_down")',
    'preserveFocusedNonFEnd',
    'foreground == true and fKeyDown == false',
    'actionType:set(0)',
    'FOCUS_POLL_INTERVAL_MS = 100'
)) {
    if (-not $main.Contains($required)) { throw "main.lua is missing: $required" }
}

foreach ($forbiddenHotPath in @(
    'table.pack(...)',
    'emit("return-ui.observed"'
)) {
    if ($main.Contains($forbiddenHotPath)) {
        throw "Allocation or logging remains in a frequent callback: $forbiddenHotPath"
    }
}

if (([regex]::Matches(
    $main,
    [regex]::Escape('actionType:set(0)')
)).Count -ne 1) {
    throw 'Expected exactly one guarded interaction-action rewrite.'
}

foreach ($forbidden in @(
    'K2_ClearTimer',
    'CheckEndCancelTimer',
    'GetPlayerPawn',
    'FindAllOf',
    'ExecuteInGameThread(function'
)) {
    if ($main.Contains($forbidden)) { throw "Unsafe obsolete path remains: $forbidden" }
}

foreach ($required in @(
    'GetForegroundWindow',
    'GetAsyncKeyState',
    'pal_focus_is_f_down',
    "is_key_down('F')"
)) {
    if (-not $native.Contains($required)) { throw "pal_focus.c is missing: $required" }
}

if (-not $license.Contains('Copyright (c) 2026 Vercadi')) {
    throw 'Upstream MIT copyright notice is missing.'
}

if ((Get-Item -LiteralPath $helperPath).Length -lt 4096) {
    throw 'Native helper DLL is unexpectedly small.'
}

Write-Output 'KeepWorking guarded-interaction validation passed.'
Write-Output "Lua SHA256: $((Get-FileHash -Algorithm SHA256 -LiteralPath $mainPath).Hash)"
Write-Output "Native source SHA256: $((Get-FileHash -Algorithm SHA256 -LiteralPath $nativePath).Hash)"
Write-Output "Native helper SHA256: $((Get-FileHash -Algorithm SHA256 -LiteralPath $helperPath).Hash)"

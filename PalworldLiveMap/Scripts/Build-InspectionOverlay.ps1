$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$source = Join-Path $root 'Diagnostics\spawn-boss-candidates.json'
$output = Join-Path $root 'App\inspection-candidates.js'
$parsed = Get-Content -Raw -LiteralPath $source | ConvertFrom-Json
$actors = @($parsed.GetEnumerator())
$excludedClassPattern = '(?i)(sound|audio|ambient|worldsettings|worldpartitionhlod|networktransmitter|playercontroller|particleeventmanager|buildobject|platform|fence|container|stageareavolume|collisionvolume|wantedpolice_(spawnerrouter|npcspawner|palspawner|combathelispawner)|^bp_item_)'
$filtered = [System.Collections.Generic.List[object]]::new()
$items = foreach ($actor in $actors) {
    if ($null -eq $actor.x -or $null -eq $actor.y) { continue }
    $x = [double]$actor.x
    $y = [double]$actor.y
    $z = if ($null -eq $actor.z) { 0 } else { [double]$actor.z }
    $className = [string]$actor.className
    $reason = $null
    if ([double]::IsNaN($x) -or [double]::IsInfinity($x) -or [double]::IsNaN($y) -or [double]::IsInfinity($y) -or [double]::IsNaN($z) -or [double]::IsInfinity($z)) { $reason = 'non-finite coordinates' }
    elseif ([Math]::Abs($x) -lt 100 -and [Math]::Abs($y) -lt 100) { $reason = 'world origin / local-space coordinates' }
    elseif ([Math]::Abs($x) -ge 950000 -or [Math]::Abs($y) -ge 950000) { $reason = 'sentinel / out-of-map coordinates' }
    elseif ($className -match '(?i)PalBossTower') { $reason = 'reconciled tower actor' }
    elseif ($className -match '(?i)DungeonFixedEntrance') { $reason = 'reconciled dungeon entrance node' }
    elseif ($className -match $excludedClassPattern) { $reason = 'non-location, build, volume, sound, or action actor' }
    if ($reason) {
        $filtered.Add([ordered]@{ id = [string]$actor.id; className = $className; reason = $reason })
        continue
    }
    $layer = switch -Regex ([string]$actor.className) {
        'PalSpawner.*FBOSS' { 'inspection-boss-spawners'; break }
        '_BOSS_C$' { 'inspection-live-bosses'; break }
        'PalSpawner' { 'inspection-pal-spawners'; break }
        'FishingSpot' { 'inspection-fishing-spots'; break }
        'Relic_Mutant' { 'lunaris-effigy'; break }
        'NPCSpawnPoint' { 'inspection-npc-spawns'; break }
        'RandomIncidentSpawner' { 'random-events'; break }
        'StaticRespawnPoint' { 'inspection-respawn-points'; break }
        'OilrigController' { 'oil-rigs'; break }
        'TowerFastTravelPoint' { 'fast-travel'; break }
        default { 'inspection-other-candidates' }
    }
    $investigationPin = $layer -like 'inspection-*'
    $stableClass = $className -replace '[^A-Za-z0-9_-]', '-'
    $stableId = 'inspection-{0}-{1}-{2}' -f $stableClass, [Math]::Round($x), [Math]::Round($y)
    $item = [ordered]@{ id = $stableId; layer = $layer; x = $x; y = $y; z = $z; className = $className; objectName = [string]$actor.objectName; investigationPin = $investigationPin }
    $item
}
$json = $items | ConvertTo-Json -Depth 4 -Compress
[System.IO.File]::WriteAllText($output, "window.ActorInspectionCandidates = Object.freeze($json);`n", [System.Text.UTF8Encoding]::new($false))
$filteredOutput = Join-Path $root 'Diagnostics\filtered-inspection-actors.json'
[System.IO.File]::WriteAllText($filteredOutput, ($filtered | ConvertTo-Json -Depth 4), [System.Text.UTF8Encoding]::new($false))
Write-Output "Wrote $($items.Count) investigation markers; filtered $($filtered.Count) non-map actors."

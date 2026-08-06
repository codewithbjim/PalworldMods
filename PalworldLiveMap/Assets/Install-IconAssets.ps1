[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$SourceDirectory
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$sourceRoot = [System.IO.Path]::GetFullPath($SourceDirectory)
$destination = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\App\assets\icons'))
$files = [ordered]@{
    'fast-travel' = 'structures\T_icon_buildObject_FastTravelPoint.webp'
    'tower' = 'structures\T_icon_buildObject_TransmissionTower.webp'
    'treasure' = 'structures\T_icon_buildObject_ItemChest.webp'
    'element-chest' = 'structures\T_icon_buildObject_WeaponChest.webp'
    'skill-fruit' = 'structures\T_icon_buildObject_Farm_SkillFruits.webp'
    'lifmunk' = 'pals\T_Carbunclo_icon_normal.webp'
    'rooby' = 'pals\T_FlameBambi_icon_normal.webp'
    'yakumo' = 'pals\T_GuardianDog_icon_normal.webp'
    'munchill' = 'pals\T_IceCrocodile_icon_normal.webp'
    'relaxaurus' = 'pals\T_LazyDragon_icon_normal.webp'
    'herbil' = 'pals\T_LeafMomonga_icon_normal.webp'
    'tanzee' = 'pals\T_Monkey_icon_normal.webp'
    'lunaris' = 'pals\T_Mutant_icon_normal.webp'
    'depresso' = 'pals\T_NegativeKoala_icon_normal.webp'
    'pengullet' = 'pals\T_Penguin_icon_normal.webp'
    'lamball' = 'pals\T_SheepBall_icon_normal.webp'
    'egg-grassland' = 'items\T_itemicon_Material_PalEgg_Leaf_01.webp'
    'egg-volcanic' = 'items\T_itemicon_Material_PalEgg_Fire_01.webp'
    'egg-sakurajima' = 'items\T_itemicon_Material_PalEgg_Dark_01.webp'
    'egg-frozen' = 'items\T_itemicon_Material_PalEgg_Ice_01.webp'
    'egg-desert' = 'items\T_itemicon_Material_PalEgg_Earth_01.webp'
    'egg-large' = 'items\T_itemicon_Material_PalEgg.webp'
    'egg-sky' = 'items\T_itemicon_Material_PalEgg_Electricity_01.webp'
    'ore' = 'items\T_itemicon_Material_CopperOre.webp'
    'coal' = 'items\T_itemicon_Material_Coal.webp'
    'sulfur' = 'items\T_itemicon_Material_Sulfur.webp'
    'quartz' = 'items\T_itemicon_Material_Quartz.webp'
    'paldium' = 'items\T_itemicon_Material_PalCrystal_Ex.webp'
    'soralite' = 'items\T_itemicon_Material_SkyIslandOre.webp'
    'berries' = 'items\T_itemicon_Material_BerrySeeds.webp'
    'mushrooms' = 'items\T_itemicon_Food_Mushroom.webp'
    'oil' = 'items\T_itemicon_Material_CrudeOil.webp'
}

if (-not [System.IO.Directory]::Exists($sourceRoot)) { throw "Icon source directory does not exist: $sourceRoot" }
[System.IO.Directory]::CreateDirectory($destination) | Out-Null
$assets = @()
foreach ($entry in $files.GetEnumerator()) {
    $source = Join-Path $sourceRoot $entry.Value
    if (-not [System.IO.File]::Exists($source)) { throw "Required icon is missing: $source" }
    $target = Join-Path $destination "$($entry.Key).webp"
    [System.IO.File]::Copy($source, $target, $true)
    $assets += [pscustomobject][ordered]@{
        name = "$($entry.Key).webp"
        bytes = (Get-Item -LiteralPath $target).Length
        sha256 = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
    }
}

$manifest = [ordered]@{ schemaVersion = 1; installedAtUtc = [DateTime]::UtcNow.ToString('o'); assets = $assets }
[System.IO.File]::WriteAllText((Join-Path $destination 'local-assets.json'), ($manifest | ConvertTo-Json -Depth 4), [System.Text.UTF8Encoding]::new($false))
$assets | Format-Table name, bytes, sha256 -AutoSize
Write-Host "Installed local-only icon assets in $destination"

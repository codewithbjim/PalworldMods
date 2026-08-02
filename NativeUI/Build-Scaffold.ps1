[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceAsset,

    [Parameter(Mandatory = $true)]
    [string]$UAssetGui,

    [string]$MappingsName = "Palworld",

    [string]$OutputDirectory
)

$ErrorActionPreference = "Stop"

function Assert-Condition {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) {
        throw $Message
    }
}

function Set-Int32LittleEndian {
    param([byte[]]$Bytes, [int]$Offset, [int]$Value)
    $encoded = [BitConverter]::GetBytes($Value)
    [Array]::Copy($encoded, 0, $Bytes, $Offset, 4)
}

function Copy-JsonObject {
    param($Value)
    return ($Value | ConvertTo-Json -Depth 100 | ConvertFrom-Json)
}

function Invoke-UAssetGui {
    param([string[]]$Arguments)
    $process = Start-Process `
        -FilePath $UAssetGui `
        -ArgumentList $Arguments `
        -Wait `
        -PassThru `
        -WindowStyle Hidden
    Assert-Condition ($process.ExitCode -eq 0) `
        "UAssetGUI exited with code $($process.ExitCode)."
}

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $PSScriptRoot "Work"
}

$sourcePath = [System.IO.Path]::GetFullPath($SourceAsset)
$sourceUexp = [System.IO.Path]::ChangeExtension($sourcePath, ".uexp")
$toolPath = [System.IO.Path]::GetFullPath($UAssetGui)
$outputRoot = [System.IO.Path]::GetFullPath($OutputDirectory)
$baseAsset = Join-Path $outputRoot "WBP_IngameConstruction.base.uasset"
$baseUexp = Join-Path $outputRoot "WBP_IngameConstruction.base.uexp"
$baseJson = Join-Path $outputRoot "WBP_IngameConstruction.base.json"
$modifiedJson = Join-Path $outputRoot "WBP_IngameConstruction.scaffold.json"
$validationJson = Join-Path $outputRoot "WBP_IngameConstruction.validation.json"
$outputAsset = Join-Path $outputRoot "WBP_IngameConstruction.uasset"
$outputUexp = Join-Path $outputRoot "WBP_IngameConstruction.uexp"

Assert-Condition (Test-Path -LiteralPath $sourcePath -PathType Leaf) `
    "Source asset was not found: $sourcePath"
Assert-Condition (Test-Path -LiteralPath $sourceUexp -PathType Leaf) `
    "Source .uexp was not found: $sourceUexp"
Assert-Condition (Test-Path -LiteralPath $toolPath -PathType Leaf) `
    "UAssetGUI was not found: $toolPath"

New-Item -ItemType Directory -Force -Path $outputRoot | Out-Null
Copy-Item -LiteralPath $sourcePath -Destination $baseAsset -Force
Copy-Item -LiteralPath $sourceUexp -Destination $baseUexp -Force

Invoke-UAssetGui @(
    "tojson",
    $baseAsset,
    $baseJson,
    "VER_UE5_1",
    $MappingsName
)

$asset = Get-Content -LiteralPath $baseJson -Raw | ConvertFrom-Json
Assert-Condition ($asset.Exports.Count -eq 170) `
    "Unexpected source export count: $($asset.Exports.Count)"
Assert-Condition ($asset.DependsMap.Count -eq 170) `
    "Unexpected source dependency-map count: $($asset.DependsMap.Count)"

$verticalIndex = -1
$slotTemplateIndex = -1
for ($index = 0; $index -lt $asset.Exports.Count; $index++) {
    switch ($asset.Exports[$index].ObjectName) {
        "VerticalBox_144" { $verticalIndex = $index }
        "VerticalBoxSlot_5" { $slotTemplateIndex = $index }
    }
}
Assert-Condition ($verticalIndex -eq 135) `
    "VerticalBox_144 moved from expected export 135."
Assert-Condition ($slotTemplateIndex -eq 144) `
    "VerticalBoxSlot_5 moved from expected export 144."

# Export array positions are zero-based. Dependency values and raw serialized
# FPackageIndex values are one-based package indices.
$newVerticalExportIndex = $asset.Exports.Count
$newSlotExportIndex = $newVerticalExportIndex + 1
$newVerticalPackageIndex = $newVerticalExportIndex + 1
$newSlotPackageIndex = $newSlotExportIndex + 1
$stockVerticalPackageIndex = $verticalIndex + 1

$stockVertical = $asset.Exports[$verticalIndex]
$stockBytes = [Convert]::FromBase64String($stockVertical.Data)
Assert-Condition ($stockBytes.Length -eq 54) `
    "Unexpected VerticalBox_144 payload length: $($stockBytes.Length)"
Assert-Condition ([BitConverter]::ToInt32($stockBytes, 2) -eq 10) `
    "VerticalBox_144 no longer contains ten slots."

$slotPackageIndices = [System.Collections.Generic.List[int]]::new()
for ($offset = 6; $offset -lt 46; $offset += 4) {
    $slotPackageIndices.Add([BitConverter]::ToInt32($stockBytes, $offset))
}
$overlayPosition = $slotPackageIndices.IndexOf(142)
Assert-Condition ($overlayPosition -ge 0) `
    "Overlay_Line slot package index 142 was not found."
$slotPackageIndices.Insert($overlayPosition, $newSlotPackageIndex)

$modifiedStockBytes = [byte[]]::new(58)
$modifiedStockBytes[0] = $stockBytes[0]
$modifiedStockBytes[1] = $stockBytes[1]
Set-Int32LittleEndian $modifiedStockBytes 2 $slotPackageIndices.Count
$writeOffset = 6
foreach ($packageIndex in $slotPackageIndices) {
    Set-Int32LittleEndian $modifiedStockBytes $writeOffset $packageIndex
    $writeOffset += 4
}
Set-Int32LittleEndian $modifiedStockBytes $writeOffset 23
Set-Int32LittleEndian $modifiedStockBytes ($writeOffset + 4) 0
$stockVertical.Data = [Convert]::ToBase64String($modifiedStockBytes)
$stockVertical.SerialSize = $modifiedStockBytes.Length
$stockDependencies = [System.Collections.Generic.List[int]]::new()
foreach ($dependency in $stockVertical.CreateBeforeSerializationDependencies) {
    $stockDependencies.Add([int]$dependency)
}
$overlayDependencyPosition = $stockDependencies.IndexOf(141)
Assert-Condition ($overlayDependencyPosition -ge 0) `
    "Overlay_Line slot dependency export 141 was not found."
$stockDependencies.Insert($overlayDependencyPosition, $newSlotPackageIndex)
$stockVertical.CreateBeforeSerializationDependencies = @($stockDependencies)

$newVertical = Copy-JsonObject $stockVertical
$newVertical.ObjectName = "VerticalBox_PP"
$newVertical.OuterIndex = 170
$newVertical.SerialOffset = 0
$newVertical.CreateBeforeSerializationDependencies = @($newSlotPackageIndex)
$newVertical.CreateBeforeCreateDependencies = @(170)
$newVerticalBytes = [byte[]]::new(14)
$newVerticalBytes[0] = $stockBytes[0]
$newVerticalBytes[1] = $stockBytes[1]
Set-Int32LittleEndian $newVerticalBytes 2 0
Set-Int32LittleEndian $newVerticalBytes 6 $newSlotPackageIndex
Set-Int32LittleEndian $newVerticalBytes 10 0
$newVertical.Data = [Convert]::ToBase64String($newVerticalBytes)
$newVertical.SerialSize = $newVerticalBytes.Length

$newSlot = Copy-JsonObject $asset.Exports[$slotTemplateIndex]
$newSlot.ObjectName = "VerticalBoxSlot_PP"
$newSlot.OuterIndex = $stockVerticalPackageIndex
$newSlot.SerialOffset = 0
$newSlot.CreateBeforeSerializationDependencies = @($newVerticalPackageIndex)
$newSlot.CreateBeforeCreateDependencies = @($stockVerticalPackageIndex)
$newSlotBytes = [Convert]::FromBase64String($newSlot.Data)
Assert-Condition ($newSlotBytes.Length -eq 22) `
    "Unexpected VerticalBoxSlot_5 payload length: $($newSlotBytes.Length)"
Set-Int32LittleEndian $newSlotBytes 10 $stockVerticalPackageIndex
Set-Int32LittleEndian $newSlotBytes 14 $newVerticalPackageIndex
$newSlot.Data = [Convert]::ToBase64String($newSlotBytes)
$newSlot.SerialSize = $newSlotBytes.Length

$asset.Exports = @($asset.Exports) + @($newVertical, $newSlot)
$emptyDependsOne = [int[]]@()
$emptyDependsTwo = [int[]]@()
$asset.DependsMap = @($asset.DependsMap) `
    + (,$emptyDependsOne) `
    + (,$emptyDependsTwo)
$asset.NameMap = @($asset.NameMap) + @(
    "VerticalBox_PP",
    "VerticalBoxSlot_PP"
)
$generation = @($asset.Generations)[0]
$generation.ExportCount = $asset.Exports.Count
$generation.NameCount = $asset.NameMap.Count

Assert-Condition ($asset.Exports.Count -eq 172) `
    "Modified export count is not 172."
Assert-Condition ($asset.DependsMap.Count -eq 172) `
    "Modified dependency-map count is not 172."

$asset | ConvertTo-Json -Depth 100 | Set-Content `
    -LiteralPath $modifiedJson `
    -Encoding UTF8

foreach ($generatedAsset in @($outputAsset, $outputUexp)) {
    if (Test-Path -LiteralPath $generatedAsset) {
        Remove-Item -LiteralPath $generatedAsset -Force
    }
}

Invoke-UAssetGui @(
    "fromjson",
    $modifiedJson,
    $outputAsset,
    $MappingsName
)

Assert-Condition (Test-Path -LiteralPath $outputAsset -PathType Leaf) `
    "UAssetGUI did not create the scaffold .uasset."
Assert-Condition (Test-Path -LiteralPath $outputUexp -PathType Leaf) `
    "UAssetGUI did not create the scaffold .uexp."

Invoke-UAssetGui @(
    "tojson",
    $outputAsset,
    $validationJson,
    "VER_UE5_1",
    $MappingsName
)
$validation = Get-Content -LiteralPath $validationJson -Raw |
    ConvertFrom-Json
Assert-Condition ($validation.Exports.Count -eq 172) `
    "The rebuilt asset did not reopen with 172 exports."
Assert-Condition ($validation.DependsMap.Count -eq 172) `
    "The rebuilt asset dependency map did not reopen with 172 entries."
$validatedVertical = @(
    $validation.Exports | Where-Object ObjectName -eq "VerticalBox_PP"
)
$validatedSlot = @(
    $validation.Exports | Where-Object ObjectName -eq "VerticalBoxSlot_PP"
)
Assert-Condition ($validatedVertical.Count -eq 1) `
    "The rebuilt asset did not contain exactly one VerticalBox_PP export."
Assert-Condition ($validatedSlot.Count -eq 1) `
    "The rebuilt asset did not contain exactly one VerticalBoxSlot_PP export."
Assert-Condition ($validatedVertical[0].OuterIndex -eq 170) `
    "VerticalBox_PP was not owned by the cooked WidgetTree."
Assert-Condition ($validatedSlot[0].OuterIndex -eq $stockVerticalPackageIndex) `
    "VerticalBoxSlot_PP was not owned by VerticalBox_144."

Write-Output "Built native scaffold: $outputAsset"
Write-Output "UAsset SHA256: $((Get-FileHash -LiteralPath $outputAsset -Algorithm SHA256).Hash)"
Write-Output "UEXP SHA256: $((Get-FileHash -LiteralPath $outputUexp -Algorithm SHA256).Hash)"

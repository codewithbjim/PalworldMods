[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$UnrealPak,

    [string]$ScaffoldDirectory,

    [string]$CookedRuntimeDirectory,

    [string]$OutputPak
)

$ErrorActionPreference = "Stop"

function Assert-Condition {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) {
        throw $Message
    }
}

if ([string]::IsNullOrWhiteSpace($ScaffoldDirectory)) {
    $ScaffoldDirectory = Join-Path $PSScriptRoot "Work"
}
if ([string]::IsNullOrWhiteSpace($OutputPak)) {
    $OutputPak = Join-Path `
        $ScaffoldDirectory `
        "PerfectPlacement_NativeUI_P.pak"
}
if ([string]::IsNullOrWhiteSpace($CookedRuntimeDirectory)) {
    $CookedRuntimeDirectory = Join-Path $PSScriptRoot "Cooked"
}

$toolPath = [System.IO.Path]::GetFullPath($UnrealPak)
$scaffoldRoot = [System.IO.Path]::GetFullPath($ScaffoldDirectory)
$outputPath = [System.IO.Path]::GetFullPath($OutputPak)
$cookedRuntimeRoot = [System.IO.Path]::GetFullPath($CookedRuntimeDirectory)
$uassetPath = Join-Path $scaffoldRoot "WBP_IngameConstruction.uasset"
$uexpPath = Join-Path $scaffoldRoot "WBP_IngameConstruction.uexp"
$responsePath = Join-Path $scaffoldRoot "PerfectPlacement_NativeUI.response.txt"
$mountRoot = "../../../Pal/Content/Pal/Blueprint/UI/UserInterface/InGame/Construction"

Assert-Condition (Test-Path -LiteralPath $toolPath -PathType Leaf) `
    "UnrealPak was not found: $toolPath"
Assert-Condition (Test-Path -LiteralPath $uassetPath -PathType Leaf) `
    "Native scaffold asset was not found: $uassetPath"
Assert-Condition (Test-Path -LiteralPath $uexpPath -PathType Leaf) `
    "Native scaffold export was not found: $uexpPath"
Assert-Condition (Test-Path -LiteralPath $cookedRuntimeRoot -PathType Container) `
    "Cooked companion runtime directory was not found: $cookedRuntimeRoot"

$requiredRuntimeAssets = @(
    "Pal\Content\Mods\PerfectPlacement\ModActor.uasset",
    "Pal\Content\Mods\PerfectPlacement\ModActor.uexp",
    "Pal\Content\Mods\PerfectPlacement\WBP_PerfectPlacement_KeyGuide.uasset",
    "Pal\Content\Mods\PerfectPlacement\WBP_PerfectPlacement_KeyGuide.uexp",
    "Pal\Content\Mods\PerfectPlacement\BP_PP_FrozenGamepadInput.uasset",
    "Pal\Content\Mods\PerfectPlacement\BP_PP_UnfrozenGamepadInput.uasset"
)
foreach ($relativeAsset in $requiredRuntimeAssets) {
    $runtimeAsset = Join-Path $cookedRuntimeRoot $relativeAsset
    Assert-Condition (Test-Path -LiteralPath $runtimeAsset -PathType Leaf) `
        "Required cooked companion asset was not found: $runtimeAsset"
}

$responseLines = [System.Collections.Generic.List[string]]::new()
$responseLines.Add(
    ('"{0}" "{1}/WBP_IngameConstruction.uasset"' -f `
        $uassetPath, $mountRoot)
)
$responseLines.Add(
    ('"{0}" "{1}/WBP_IngameConstruction.uexp"' -f `
        $uexpPath, $mountRoot)
)
$runtimeFiles = Get-ChildItem -LiteralPath $cookedRuntimeRoot -Recurse -File |
    Sort-Object FullName
foreach ($runtimeFile in $runtimeFiles) {
    $relativePath = $runtimeFile.FullName.Substring(
        $cookedRuntimeRoot.Length
    ).TrimStart('\').Replace('\', '/')
    $responseLines.Add(
        ('"{0}" "../../../{1}"' -f $runtimeFile.FullName, $relativePath)
    )
}
$responseLines | Set-Content -LiteralPath $responsePath -Encoding ASCII

$outputParent = Split-Path -Parent $outputPath
New-Item -ItemType Directory -Force -Path $outputParent | Out-Null
if (Test-Path -LiteralPath $outputPath) {
    Remove-Item -LiteralPath $outputPath -Force
}

$arguments = @(
    $outputPath,
    "-Create=$responsePath",
    "-compress"
)
$process = Start-Process `
    -FilePath $toolPath `
    -ArgumentList $arguments `
    -Wait `
    -PassThru `
    -WindowStyle Hidden
Assert-Condition ($process.ExitCode -eq 0) `
    "UnrealPak exited with code $($process.ExitCode)."
Assert-Condition (Test-Path -LiteralPath $outputPath -PathType Leaf) `
    "UnrealPak did not create the native UI pak."
Assert-Condition ((Get-Item -LiteralPath $outputPath).Length -gt 0) `
    "The native UI pak is empty."

$pakHash = (Get-FileHash -LiteralPath $outputPath -Algorithm SHA256).Hash
$hashPath = "$outputPath.sha256"
("$pakHash *$([System.IO.Path]::GetFileName($outputPath))") |
    Set-Content -LiteralPath $hashPath -Encoding ASCII

Write-Output "Built native UI pak: $outputPath"
Write-Output "Included cooked companion runtime files: $($runtimeFiles.Count)"
Write-Output "PAK SHA256: $pakHash"
Write-Output "Checksum: $hashPath"

param(
    [string]$Version = '0.1.0'
)

$ErrorActionPreference = 'Stop'

$modRoot = $PSScriptRoot
$repoRoot = Split-Path -Parent $modRoot
$distRoot = Join-Path $repoRoot 'Release\Dist'
$archivePath = Join-Path $distRoot "KeepWorking-$Version.zip"
$stageRoot = Join-Path ([System.IO.Path]::GetTempPath()) (
    'KeepWorking-release-' + [guid]::NewGuid().ToString('N')
)
$modDestination = Join-Path $stageRoot 'Pal\Binaries\Win64\ue4ss\Mods\KeepWorking'

try {
    $manifest = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $modRoot 'Info.json') |
        ConvertFrom-Json
    if ($manifest.PackageName -ne 'KeepWorking') {
        throw "Unexpected package name '$($manifest.PackageName)'."
    }
    if ($manifest.Version -ne $Version) {
        throw "Info.json version '$($manifest.Version)' does not match '$Version'."
    }

    & (Join-Path $modRoot 'tests\validate.ps1')

    New-Item -ItemType Directory -Path $modDestination -Force | Out-Null
    New-Item -ItemType Directory -Path $distRoot -Force | Out-Null

    foreach ($relativePath in @(
        'enabled.txt',
        'Info.json',
        'LICENSE',
        'README.md',
        'CHANGELOG.md',
        'Scripts\main.lua',
        'Scripts\AltTabWorkContinuationFocus.dll'
    )) {
        $sourcePath = Join-Path $modRoot $relativePath
        $destinationPath = Join-Path $modDestination $relativePath
        $destinationDirectory = Split-Path -Parent $destinationPath
        New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
        Copy-Item -LiteralPath $sourcePath -Destination $destinationPath -Force
    }

    if (Test-Path -LiteralPath $archivePath) {
        Remove-Item -LiteralPath $archivePath -Force
    }
    Compress-Archive -Path (Join-Path $stageRoot '*') `
        -DestinationPath $archivePath -CompressionLevel Optimal

    Write-Output "Created $archivePath"
}
finally {
    if (Test-Path -LiteralPath $stageRoot) {
        Remove-Item -LiteralPath $stageRoot -Recurse -Force
    }
}

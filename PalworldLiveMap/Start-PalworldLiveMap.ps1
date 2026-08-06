[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = [System.IO.Path]::GetFullPath($PSScriptRoot)
$electron = Join-Path $root 'node_modules\electron\dist\electron.exe'
$reader = Join-Path $root 'Reader\bin\Release\net8.0-windows\PalworldLiveMap.Reader.exe'
$worldMap = Join-Path $root 'App\assets\maps\T_WorldMap.webp'
$treeMap = Join-Path $root 'App\assets\maps\T_TreeMap.webp'
$palCatalog = Join-Path $root 'App\assets\pals\pal-catalog.js'

foreach ($required in @($electron, $reader, $worldMap, $treeMap, $palCatalog)) {
    if (-not [System.IO.File]::Exists($required)) {
        throw "Required desktop app file is missing: $required"
    }
}

Start-Process -FilePath $electron -ArgumentList @($root) -WorkingDirectory $root

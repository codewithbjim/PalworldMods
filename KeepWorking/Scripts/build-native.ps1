param()

$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$source = Join-Path $projectRoot 'Native\pal_focus.c'
$scriptsDirectory = Join-Path $projectRoot 'Scripts'
$outputDll = Join-Path $scriptsDirectory 'AltTabWorkContinuationFocus.dll'
$buildDirectory = Join-Path $projectRoot 'build'

if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
    throw "Missing native source: $source"
}

$vswhereCandidates = @(
    (Get-Command vswhere.exe -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty Source),
    (Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'),
    (Join-Path $env:ProgramFiles 'Microsoft Visual Studio\Installer\vswhere.exe')
) | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) } |
    Select-Object -Unique
$vswhere = $vswhereCandidates | Select-Object -First 1
if (-not $vswhere) {
    throw 'Visual Studio Installer\vswhere.exe was not found.'
}

$vsInstall = (& $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath).Trim()
if ([string]::IsNullOrWhiteSpace($vsInstall)) {
    throw 'No Visual Studio installation with the x64 C++ toolchain was found.'
}

$devCommand = Join-Path $vsInstall 'Common7\Tools\VsDevCmd.bat'
if (-not (Test-Path -LiteralPath $devCommand -PathType Leaf)) {
    throw "Visual Studio developer command file is missing: $devCommand"
}

New-Item -ItemType Directory -Force -Path $buildDirectory, $scriptsDirectory | Out-Null

$arguments = @(
    '/nologo',
    '/TC',
    '/LD',
    '/O2',
    '/MT',
    '/GS',
    '/guard:cf',
    '/W4',
    '/WX',
    '/Brepro',
    '/DWIN32_LEAN_AND_MEAN',
    '/DNDEBUG',
    $source,
    '/link',
    '/NOLOGO',
    '/MACHINE:X64',
    '/DYNAMICBASE',
    '/NXCOMPAT',
    '/GUARD:CF',
    '/BREPRO',
    '/INCREMENTAL:NO',
    "/OUT:$outputDll",
    "/IMPLIB:$(Join-Path $buildDirectory 'pal_focus.lib')",
    "/PDB:$(Join-Path $buildDirectory 'pal_focus.pdb')",
    'User32.lib',
    'Kernel32.lib'
)

Push-Location $buildDirectory
try {
    $quotedArguments = $arguments | ForEach-Object {
        '"' + $_.Replace('"', '""') + '"'
    }
    $compileCommand = 'call "' + $devCommand +
        '" -arch=x64 -host_arch=x64 >nul && cl.exe ' +
        ($quotedArguments -join ' ')

    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $compilerOutput = & $env:ComSpec /d /s /c $compileCommand 2>&1
    $compilerExitCode = $LASTEXITCODE
    $ErrorActionPreference = $previousErrorActionPreference
    if ($compilerExitCode -ne 0) {
        throw "Native helper build failed:`n$($compilerOutput -join [Environment]::NewLine)"
    }
}
finally {
    $ErrorActionPreference = $previousErrorActionPreference
    Pop-Location
}

$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $outputDll).Hash
$sourceHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $source).Hash
$buildManifest = Join-Path $buildDirectory 'build-manifest.json'
$compilerVersion = "MSVC x64 from $vsInstall"
[ordered]@{
    source = 'Native/pal_focus.c'
    sourceSha256 = $sourceHash
    output = 'Scripts/AltTabWorkContinuationFocus.dll'
    outputSha256 = $hash
    compiler = $compilerVersion
    configuration = 'x64 /O2 /MT /Brepro /INCREMENTAL:NO'
} | ConvertTo-Json | Set-Content -LiteralPath $buildManifest -Encoding UTF8

Write-Output "Built native foreground helper: $outputDll"
Write-Output "Compiler: $compilerVersion"
Write-Output "Source SHA256: $sourceHash"
Write-Output "SHA256: $hash"
Write-Output "Build manifest: $buildManifest"
$compilerOutput | Write-Output

#Requires -Version 5.1
<#
.SYNOPSIS
    Build MeshLab and produce the Windows installer in one command.
.DESCRIPTION
    Runs the CMake configure step, builds the INSTALL target in Release|x64,
    deploys Qt and runtime resources into <repo>\install, then packages it
    with NSIS. The installer is written to <repo>\packages.
.PARAMETER QtDir
    Qt 5.15 MSVC 2019 64-bit installation directory.
.PARAMETER Makensis
    Path to makensis.exe. Auto-detected from PATH and the default NSIS
    installation directories when omitted.
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Windows\build_installer.ps1
#>
[CmdletBinding()]
param(
    [string]$QtDir = (Join-Path $env:USERPROFILE 'Qt\5.15.2\msvc2019_64'),
    [string]$Makensis = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$BuildDir = Join-Path $RepoRoot 'build'
$InstallDir = Join-Path $RepoRoot 'install'
$PackagesDir = Join-Path $RepoRoot 'packages'
$ResourcesDir = Join-Path $RepoRoot 'resources'

function Invoke-Checked {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string[]]$Arguments = @(),
        [Parameter(Mandatory = $true)][string]$Description
    )
    & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Description failed (exit code $LASTEXITCODE)."
    }
}

function Get-CmakePath {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (Test-Path $vswhere) {
        $vsPath = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath | Select-Object -First 1
        if ($vsPath) {
            $candidate = Join-Path $vsPath 'Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe'
            if (Test-Path $candidate) {
                return $candidate
            }
        }
    }
    $command = Get-Command cmake -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }
    throw 'cmake was not found. Install Visual Studio 2022 with the C++ workload, or install CMake 3.18+ and add it to PATH.'
}

function Resolve-Makensis {
    $command = Get-Command makensis -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }
    $candidates = @(
        (Join-Path ${env:ProgramFiles(x86)} 'NSIS\makensis.exe'),
        (Join-Path $env:ProgramFiles 'NSIS\makensis.exe')
    )
    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) {
            return $candidate
        }
    }
    throw 'makensis.exe was not found. Install NSIS (winget install --id NSIS.NSIS -e) or pass -Makensis <path>.'
}

$versionFile = Join-Path $RepoRoot 'ML_VERSION'
if (-not (Test-Path $versionFile)) {
    throw "'$versionFile' was not found."
}
$Version = (Get-Content $versionFile -Raw).Trim()
if ([string]::IsNullOrWhiteSpace($Version)) {
    throw "'$versionFile' is empty."
}

Write-Host "=== [1/4] Configuring CMake (version $Version) ==="
& (Join-Path $PSScriptRoot 'configure.ps1') -QtDir $QtDir -BuildDir $BuildDir

Write-Host '=== [2/4] Building INSTALL target (Release|x64) ==='
$cmake = Get-CmakePath
Invoke-Checked -FilePath $cmake -Arguments @('--build', $BuildDir, '--config', 'Release', '--target', 'INSTALL', '--parallel') -Description 'Build'

$meshlabExe = Join-Path $InstallDir 'meshlab.exe'
if (-not (Test-Path $meshlabExe)) {
    throw "The INSTALL target finished but '$meshlabExe' was not created."
}

Write-Host '=== [3/4] Deploying Qt and runtime files ==='
$windeployqt = Join-Path $QtDir 'bin\windeployqt.exe'
if (-not (Test-Path $windeployqt)) {
    throw "windeployqt.exe was not found under '$QtDir'."
}

Invoke-Checked -FilePath $windeployqt -Arguments @($meshlabExe) -Description 'windeployqt (meshlab.exe)'

$sketchfabPlugin = Join-Path $InstallDir 'plugins\filter_sketchfab.dll'
if (Test-Path $sketchfabPlugin) {
    Invoke-Checked -FilePath $windeployqt -Arguments @($sketchfabPlugin, '--libdir', $InstallDir) -Description 'windeployqt (filter_sketchfab.dll)'
}

# Some upstream builds place the IFX DLLs in a lib\meshlab subdirectory.
$ifxDir = Join-Path $InstallDir 'lib\meshlab'
if (Test-Path $ifxDir) {
    Get-ChildItem -Path $ifxDir -Filter 'IFX*' -File | Move-Item -Destination $InstallDir -Force
}

foreach ($name in @('LICENSE.txt', 'privacy.txt')) {
    $source = Join-Path $ResourcesDir $name
    if (-not (Test-Path $source)) {
        throw "'$source' was not found."
    }
    Copy-Item -Path $source -Destination $InstallDir -Force
}

Get-ChildItem -Path $InstallDir -Recurse -Filter '*.lib' -File | Remove-Item -Force

$vcRedist = Join-Path $InstallDir 'vc_redist.x64.exe'
if (-not (Test-Path $vcRedist)) {
    Write-Host 'Downloading vc_redist.x64.exe...'
    $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
    if ($curl) {
        Invoke-Checked -FilePath $curl.Source -Arguments @('-L', '-o', $vcRedist, 'https://aka.ms/vs/17/release/vc_redist.x64.exe') -Description 'Downloading vc_redist'
    }
    else {
        Invoke-WebRequest -Uri 'https://aka.ms/vs/17/release/vc_redist.x64.exe' -OutFile $vcRedist -UseBasicParsing
    }
    if (-not (Test-Path $vcRedist)) {
        throw 'vc_redist.x64.exe could not be downloaded.'
    }
}

Write-Host '=== [4/4] Building NSIS installer ==='
if ([string]::IsNullOrWhiteSpace($Makensis)) {
    $Makensis = Resolve-Makensis
}

$templatePath = Join-Path $ResourcesDir 'windows\meshlab.nsi'
$finalNsi = Join-Path $InstallDir 'meshlab_final.nsi'
$nshNames = @('ExecWaitJob.nsh', 'FileAssociation.nsh')
$tempFiles = @($finalNsi) + ($nshNames | ForEach-Object { Join-Path $InstallDir $_ })

$nsi = [System.IO.File]::ReadAllText($templatePath)
$nsi = $nsi.Replace('MESHLAB_VERSION', $Version)
$nsi = $nsi.Replace('DISTRIB_PATH', '.')
[System.IO.File]::WriteAllText($finalNsi, $nsi, [System.Text.Encoding]::ASCII)

foreach ($name in $nshNames) {
    Copy-Item -Path (Join-Path $ResourcesDir "windows\$name") -Destination $InstallDir -Force
}

# Installers left behind by an earlier run would otherwise be packed into the new one.
Get-ChildItem -Path $InstallDir -Filter 'MeshLab*-windows.exe' -File | Remove-Item -Force

$generatedInstaller = Join-Path $InstallDir "MeshLab$Version-windows.exe"
$targetInstaller = Join-Path $PackagesDir "MeshLab$Version-windows_x86_64.exe"

try {
    Push-Location $InstallDir
    try {
        Invoke-Checked -FilePath $Makensis -Arguments @($finalNsi) -Description 'makensis'
    }
    finally {
        Pop-Location
    }

    if (-not (Test-Path $generatedInstaller)) {
        throw "NSIS finished but '$generatedInstaller' was not created."
    }
    if (-not (Test-Path $PackagesDir)) {
        New-Item -ItemType Directory -Path $PackagesDir | Out-Null
    }
    Move-Item -Path $generatedInstaller -Destination $targetInstaller -Force
}
finally {
    foreach ($file in $tempFiles) {
        if (Test-Path $file) {
            Remove-Item -Path $file -Force
        }
    }
}

Write-Host ''
Write-Host "Installer created: $targetInstaller"
Write-Host "Size: $([math]::Round((Get-Item $targetInstaller).Length / 1MB, 1)) MB"

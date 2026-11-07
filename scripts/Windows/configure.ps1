#Requires -Version 5.1
<#
.SYNOPSIS
    Generate the Visual Studio 2022 solution for MeshLab without compiling.
.DESCRIPTION
    Runs only the CMake configure step with the Visual Studio 17 2022
    generator. No source files are compiled. The resulting solution is
    <BuildDir>\MeshLab.sln.
.PARAMETER QtDir
    Qt 5.15 MSVC 2019 64-bit installation directory.
.PARAMETER BuildDir
    Directory where CMake generates the solution. Defaults to <repo>\build.
#>
[CmdletBinding()]
param(
    [string]$QtDir = (Join-Path $env:USERPROFILE 'Qt\5.15.2\msvc2019_64'),
    [string]$BuildDir = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
if ([string]::IsNullOrWhiteSpace($BuildDir)) {
    $BuildDir = Join-Path $RepoRoot 'build'
}
elseif (-not [System.IO.Path]::IsPathRooted($BuildDir)) {
    $BuildDir = Join-Path $RepoRoot $BuildDir
}

$qtConfig = Join-Path $QtDir 'lib\cmake\Qt5\Qt5Config.cmake'
if (-not (Test-Path $qtConfig)) {
    throw "Qt 5.15 not found at '$QtDir'. Install it or pass -QtDir <path to msvc2019_64>."
}

$vcglib = Join-Path $RepoRoot 'src\vcglib\CMakeLists.txt'
if (-not (Test-Path $vcglib)) {
    Write-Host 'Initializing git submodules...'
    & git -C $RepoRoot submodule update --init --recursive
    if ($LASTEXITCODE -ne 0) {
        throw 'git submodule update failed.'
    }
}

$cmake = $null
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
if (Test-Path $vswhere) {
    $vsPath = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath | Select-Object -First 1
    if ($vsPath) {
        $candidate = Join-Path $vsPath 'Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe'
        if (Test-Path $candidate) {
            $cmake = $candidate
        }
    }
}
if (-not $cmake) {
    $cmakeCommand = Get-Command cmake -ErrorAction SilentlyContinue
    if ($cmakeCommand) {
        $cmake = $cmakeCommand.Source
    }
}
if (-not $cmake) {
    throw 'cmake was not found. Install Visual Studio 2022 with the C++ workload, or install CMake 3.18+ and add it to PATH.'
}

# The user-wide vcpkg MSBuild integration makes CMake's try_compile link all
# installed vcpkg libraries, which can make POSIX functions look available on
# Windows. Disable it for this configure process only.
$env:VcpkgEnabled = 'false'
$env:VCPkgLocalAppDataDisabled = 'true'

Write-Host "Using CMake: $cmake"
Write-Host "Generating Visual Studio 2022 solution in '$BuildDir'..."
# Compatibility options validated on Windows:
#   /utf-8                 third-party sources under a non-UTF-8 ANSI code page
#                          (e.g. Chinese Windows, CP936) otherwise raise C4819
#   -DHAVE_GETTIMEOFDAY=0  MSVC has no gettimeofday; prevents a false-positive
#                          CMake probe when vcpkg libraries provide one
#   -DE57_RELEASE_LTO=OFF  libE57Format's /GL objects cannot be parsed by
#                          `cmake -E __create_def` with auto-export enabled
& $cmake -S $RepoRoot -B $BuildDir `
    -G 'Visual Studio 17 2022' -A x64 `
    "-DCMAKE_PREFIX_PATH=$QtDir" `
    "-DCMAKE_INSTALL_PREFIX=$(Join-Path $RepoRoot 'install')" `
    '-DCMAKE_C_FLAGS=/DWIN32 /D_WINDOWS /utf-8' `
    '-DCMAKE_CXX_FLAGS=/DWIN32 /D_WINDOWS /GR /EHsc /utf-8' `
    '-DHAVE_GETTIMEOFDAY=0' `
    '-DE57_RELEASE_LTO=OFF'
if ($LASTEXITCODE -ne 0) {
    throw "CMake configuration failed (exit code $LASTEXITCODE)."
}

$solution = Join-Path $BuildDir 'MeshLab.sln'
if (-not (Test-Path $solution)) {
    throw "CMake finished but '$solution' was not generated."
}

Write-Host ''
Write-Host "Solution generated: $solution"
Write-Host 'No source files were compiled.'
Write-Host ''
Write-Host 'Next steps:'
Write-Host '  1. Open the solution in Visual Studio 2022.'
Write-Host '  2. Select the Release | x64 configuration.'
Write-Host '  3. Build the INSTALL target to produce a runnable install\meshlab.exe.'

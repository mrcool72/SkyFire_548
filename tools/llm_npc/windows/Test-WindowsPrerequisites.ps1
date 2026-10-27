#Requires -Version 5.1
<#
.SYNOPSIS
Read-only SkyFire Windows Server 2022 build prerequisites check.
.DESCRIPTION
Does not install software, edit registry, set system PATH, or change files.
#>
[CmdletBinding()]
param(
    [string] $BoostRoot = 'C:\local\boost_1_91_0',
    [string] $OpenSslRoot = 'C:\Program Files\OpenSSL-Win64',
    [string] $MySqlRoot = 'C:\tools\mysql\current'
)

$ErrorActionPreference = 'Stop'
$warningCount = 0

function Check-Command([string] $Name) {
    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if ($command) {
        Write-Host ('[OK]   {0}: {1}' -f $Name, $command.Source) -ForegroundColor Green
        return
    }
    Write-Host ('[WARN] {0} is not on PATH' -f $Name) -ForegroundColor Yellow
    $script:warningCount++
}

function Check-Directory([string] $Description, [string] $Path) {
    if (Test-Path -LiteralPath $Path -PathType Container) {
        Write-Host ('[OK]   {0}: {1}' -f $Description, $Path) -ForegroundColor Green
        return
    }
    Write-Host ('[WARN] Missing {0}: {1}' -f $Description, $Path) -ForegroundColor Yellow
    $script:warningCount++
}

$os = Get-CimInstance Win32_OperatingSystem
Write-Host ('Windows: {0} ({1})' -f $os.Caption, $os.OSArchitecture)
if ($os.OSArchitecture -notmatch '64') {
    Write-Host '[WARN] A 64-bit Windows installation is required.' -ForegroundColor Yellow
    $warningCount++
}
if ($os.Caption -notmatch 'Server 2022') {
    Write-Host '[INFO] This script targets Server 2022; you are checking another Windows edition.'
}

Check-Command 'git'
Check-Command 'gh'
Check-Command 'cmake'
Check-Command 'python'

$vswhere = Join-Path ([Environment]::GetFolderPath('ProgramFilesX86')) 'Microsoft Visual Studio\Installer\vswhere.exe'
if (Test-Path -LiteralPath $vswhere) {
    $vs = & $vswhere -latest -products '*' -requires 'Microsoft.VisualStudio.Component.VC.Tools.x86.x64' -property installationPath
    if ($LASTEXITCODE -eq 0 -and $vs) {
        Write-Host ('[OK]   Visual Studio C++ toolset: {0}' -f $vs) -ForegroundColor Green
    }
    else {
        Write-Host '[WARN] A Visual Studio C++ development workload was not detected.' -ForegroundColor Yellow
        $warningCount++
    }
}
else {
    Write-Host '[WARN] vswhere.exe not found (Visual Studio 2022 C++ toolset may be missing).' -ForegroundColor Yellow
    $warningCount++
}

Check-Directory 'Boost 1.91.0 root' $BoostRoot
Check-Directory 'OpenSSL 4.0.1 root' $OpenSslRoot
Check-Directory 'MySQL client development root' $MySqlRoot

$legacy = @(
    (Join-Path $OpenSslRoot 'lib\ossl-modules\legacy.dll'),
    (Join-Path $OpenSslRoot 'bin\legacy.dll'),
    (Join-Path $OpenSslRoot 'lib\VC\x64\MD\liblegacy.lib')
)
if ($legacy | Where-Object { Test-Path -LiteralPath $_ }) {
    Write-Host '[OK]   At least one OpenSSL legacy provider artifact was found.' -ForegroundColor Green
}
else {
    Write-Host '[WARN] Legacy OpenSSL provider was not found in the standard paths.' -ForegroundColor Yellow
    $warningCount++
}

$cmakeCmd = Get-Command 'cmake' -ErrorAction SilentlyContinue
if ($cmakeCmd) {
    Write-Host 'CMake reported version:' -ForegroundColor Cyan
    & cmake --version | Select-Object -First 1
}
Write-Host ('Prerequisite warnings: {0}' -f $warningCount)
Write-Host 'This tool checks presence, not binary compatibility or a successful C++ build.'

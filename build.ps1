<#
.SYNOPSIS
    Compiles install-gui.ps1 into PD2ModsInstaller.exe using PS2EXE.
.DESCRIPTION
    Installs the ps2exe module (CurrentUser scope) if missing, then builds a
    windowed (no-console) exe. Run this once to produce the installer; commit
    the resulting .exe so users can download and double-click it.
#>
[CmdletBinding()]
param(
    [string]$Source = (Join-Path $PSScriptRoot 'install-gui.ps1'),
    [string]$Output = (Join-Path $PSScriptRoot 'PD2ModsInstaller.exe')
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Module -ListAvailable -Name ps2exe)) {
    Write-Host 'Installing ps2exe module (CurrentUser scope)...' -ForegroundColor Cyan
    Install-Module -Name ps2exe -Scope CurrentUser -Force -AllowClobber
}
Import-Module ps2exe

Write-Host "Building $Output ..." -ForegroundColor Cyan
Invoke-ps2exe `
    -inputFile  $Source `
    -outputFile $Output `
    -noConsole `
    -title       'PAYDAY 2 Mods Installer' `
    -product     'PAYDAY 2 Mods' `
    -company     'rroig7' `
    -requireAdmin:$false

if (Test-Path $Output) {
    Write-Host "Done: $Output" -ForegroundColor Green
} else {
    throw 'Build failed: output exe not produced.'
}

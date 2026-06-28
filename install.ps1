<#
.SYNOPSIS
    Installs the pd2-mods bundle into your PAYDAY 2 folder.

.DESCRIPTION
    Downloads the latest files from GitHub (rroig7/pd2-mods), auto-detects your
    PAYDAY 2 Steam install folder, and copies WSOCK32.dll (the SuperBLT loader)
    and the mods/ folder into it.

.PARAMETER GameDir
    Optional. Path to your PAYDAY 2 install folder. If omitted, the script
    auto-detects it from Steam.

.EXAMPLE
    irm https://raw.githubusercontent.com/rroig7/pd2-mods-installer/main/install.ps1 | iex

.EXAMPLE
    .\install.ps1 -GameDir "D:\Games\PAYDAY 2"
#>

[CmdletBinding()]
param(
    [string]$GameDir
)

$ErrorActionPreference = 'Stop'

# GitHub source
$Repo      = 'rroig7/pd2-mods'
$Branch    = 'main'
$ZipUrl    = "https://github.com/$Repo/archive/refs/heads/$Branch.zip"
$AppId     = '218620'   # PAYDAY 2 Steam App ID
$GameExe   = 'payday2_win32_release.exe'

function Write-Step($msg)  { Write-Host "==> $msg" -ForegroundColor Cyan }
function Write-Ok($msg)    { Write-Host "    $msg" -ForegroundColor Green }
function Write-Warn2($msg) { Write-Host "    $msg" -ForegroundColor Yellow }

# --- Locate Steam ------------------------------------------------------------
function Get-SteamPath {
    foreach ($key in @('HKCU:\Software\Valve\Steam',
                       'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam',
                       'HKLM:\SOFTWARE\Valve\Steam')) {
        try {
            $item = Get-ItemProperty -Path $key -ErrorAction Stop
            $p = $item.SteamPath
            if (-not $p) { $p = $item.InstallPath }
            if ($p -and (Test-Path $p)) { return (Resolve-Path $p).Path }
        } catch { }
    }
    return $null
}

# --- Find every Steam library folder ----------------------------------------
function Get-SteamLibraries($steamPath) {
    $libs = New-Object System.Collections.Generic.List[string]
    if ($steamPath) { $libs.Add($steamPath) }

    $vdf = Join-Path $steamPath 'steamapps\libraryfolders.vdf'
    if (Test-Path $vdf) {
        $text = Get-Content $vdf -Raw
        foreach ($m in [regex]::Matches($text, '"path"\s*"([^"]+)"')) {
            # vdf escapes backslashes as \\
            $p = $m.Groups[1].Value -replace '\\\\', '\'
            if ((Test-Path $p) -and ($libs -notcontains $p)) { $libs.Add($p) }
        }
    }
    return $libs
}

# --- Auto-detect the PAYDAY 2 install folder --------------------------------
function Find-Payday2 {
    $steam = Get-SteamPath
    if ($steam) { Write-Ok "Steam found at: $steam" }
    else        { Write-Warn2 'Steam registry entry not found; trying common paths.' }

    $candidates = New-Object System.Collections.Generic.List[string]

    foreach ($lib in (Get-SteamLibraries $steam)) {
        # Preferred: read the app manifest for the exact install dir name
        $acf = Join-Path $lib "steamapps\appmanifest_$AppId.acf"
        if (Test-Path $acf) {
            $acfText = Get-Content $acf -Raw
            $im = [regex]::Match($acfText, '"installdir"\s*"([^"]+)"')
            if ($im.Success) {
                $candidates.Add((Join-Path $lib ("steamapps\common\" + $im.Groups[1].Value)))
            }
        }
        # Fallback: the default folder name
        $candidates.Add((Join-Path $lib 'steamapps\common\PAYDAY 2'))
    }

    # Last-ditch hardcoded defaults
    $candidates.Add('C:\Program Files (x86)\Steam\steamapps\common\PAYDAY 2')

    foreach ($c in $candidates) {
        if (Test-Path (Join-Path $c $GameExe)) { return (Resolve-Path $c).Path }
    }
    return $null
}

# --- Main --------------------------------------------------------------------
try {
    [Net.ServicePointManager]::SecurityProtocol = `
        [Net.ServicePointManager]::SecurityProtocol -bor 3072  # TLS 1.2

    Write-Host ''
    Write-Host '  PAYDAY 2 Mods Installer' -ForegroundColor Magenta
    Write-Host '  =======================' -ForegroundColor Magenta
    Write-Host ''

    # 1. Resolve the game directory
    Write-Step 'Detecting PAYDAY 2 install folder...'
    if (-not $GameDir) { $GameDir = Find-Payday2 }

    if (-not $GameDir -or -not (Test-Path (Join-Path $GameDir $GameExe))) {
        Write-Warn2 'Could not auto-detect a valid PAYDAY 2 folder.'
        $GameDir = Read-Host 'Enter the full path to your PAYDAY 2 folder'
        if (-not (Test-Path (Join-Path $GameDir $GameExe))) {
            throw "That folder doesn't contain $GameExe. Aborting."
        }
    }
    Write-Ok "Installing to: $GameDir"

    # 2. Download the bundle from GitHub
    $work = Join-Path ([IO.Path]::GetTempPath()) ("pd2mods_" + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $work -Force | Out-Null
    $zip = Join-Path $work 'bundle.zip'

    Write-Step "Downloading mods from GitHub ($Repo)..."
    Invoke-WebRequest -Uri $ZipUrl -OutFile $zip -UseBasicParsing
    Write-Ok 'Download complete.'

    Write-Step 'Extracting...'
    Expand-Archive -Path $zip -DestinationPath $work -Force
    $extracted = Get-ChildItem -Path $work -Directory |
                 Where-Object { $_.Name -like 'pd2-mods-*' } |
                 Select-Object -First 1
    if (-not $extracted) { throw 'Extraction failed: source folder not found.' }
    $src = $extracted.FullName

    # 3. Copy the loader DLL
    Write-Step 'Copying SuperBLT loader (WSOCK32.dll)...'
    $dll = Join-Path $src 'WSOCK32.dll'
    if (Test-Path $dll) {
        Copy-Item -Path $dll -Destination $GameDir -Force
        Write-Ok 'WSOCK32.dll installed.'
    } else {
        Write-Warn2 'WSOCK32.dll not present in bundle; skipping.'
    }

    # 4. Copy the mods folder (merge)
    Write-Step 'Copying mods folder...'
    $srcMods = Join-Path $src 'mods'
    $dstMods = Join-Path $GameDir 'mods'
    if (-not (Test-Path $dstMods)) { New-Item -ItemType Directory -Path $dstMods -Force | Out-Null }
    # Copy the *contents* of mods\ so existing mods aren't wiped, only merged/updated
    Copy-Item -Path (Join-Path $srcMods '*') -Destination $dstMods -Recurse -Force
    Write-Ok 'Mods installed.'

    # 5. Clean up
    Remove-Item -Path $work -Recurse -Force -ErrorAction SilentlyContinue

    Write-Host ''
    Write-Host '  Done! Launch PAYDAY 2 through Steam to play with mods.' -ForegroundColor Green
    Write-Host '  A "Mods" entry will appear in the in-game Options menu.' -ForegroundColor Green
    Write-Host ''
}
catch {
    Write-Host ''
    Write-Host "  INSTALL FAILED: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ''
    exit 1
}

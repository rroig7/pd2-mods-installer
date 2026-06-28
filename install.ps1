<#
.SYNOPSIS
    Installs / updates the pd2-mods bundle in your PAYDAY 2 folder.

.DESCRIPTION
    Auto-detects your PAYDAY 2 Steam install folder, downloads the latest files
    from GitHub (rroig7/pd2-mods), and compares them against what's already
    installed. If the mods are missing it installs them; if they're already
    present it only prompts to update the files that actually changed. Volatile
    user state (logs, saves, downloads) is never compared or overwritten.

.PARAMETER GameDir
    Optional. Path to your PAYDAY 2 install folder. Auto-detected if omitted.

.PARAMETER Force
    Skip the confirmation prompt and apply changes automatically.

.EXAMPLE
    irm https://raw.githubusercontent.com/rroig7/pd2-mods-installer/main/install.ps1 | iex

.EXAMPLE
    .\install.ps1 -GameDir "D:\Games\PAYDAY 2" -Force
#>

[CmdletBinding()]
param(
    [string]$GameDir,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

# GitHub source
$Repo      = 'rroig7/pd2-mods'
$Branch    = 'main'
$ZipUrl    = "https://github.com/$Repo/archive/refs/heads/$Branch.zip"
$AppId     = '218620'   # PAYDAY 2 Steam App ID
$GameExe   = 'payday2_win32_release.exe'

# Paths that are per-user runtime state: never compared, never overwritten.
$VolatilePrefixes = @('mods\logs\', 'mods\saves\', 'mods\downloads\')


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

# --- Update detection helpers -----------------------------------------------
function Test-Volatile($rel) {
    foreach ($p in $VolatilePrefixes) { if ($rel -like "$p*") { return $true } }
    return $false
}

# True if the bundle already looks installed in $gameDir.
function Test-ModsInstalled($gameDir) {
    return (Test-Path (Join-Path $gameDir 'WSOCK32.dll')) -and
           (Test-Path (Join-Path $gameDir 'mods\base'))
}

# Every installable file in the bundle (relative paths), excluding volatile state.
function Get-BundleFiles($src) {
    $files = New-Object System.Collections.Generic.List[string]
    if (Test-Path (Join-Path $src 'WSOCK32.dll')) { $files.Add('WSOCK32.dll') }
    foreach ($f in Get-ChildItem (Join-Path $src 'mods') -Recurse -File) {
        $rel = $f.FullName.Substring($src.Length).TrimStart('\')
        if (-not (Test-Volatile $rel)) { $files.Add($rel) }
    }
    return $files
}

# True if two files differ in content. Binary files (those containing a NUL
# byte) compare byte-exact; text files are compared with line endings normalized
# so a CRLF-vs-LF-only difference (e.g. from git autocrlf) is not a "change".
function Test-FileChanged($srcFile, $destFile) {
    if ((Get-FileHash $srcFile -Algorithm SHA1).Hash -eq
        (Get-FileHash $destFile -Algorithm SHA1).Hash) { return $false }
    $a = [IO.File]::ReadAllBytes($srcFile)
    $b = [IO.File]::ReadAllBytes($destFile)
    if (($a -contains 0) -or ($b -contains 0)) { return $true }   # binary
    $sa = [Text.Encoding]::UTF8.GetString($a) -replace "`r`n", "`n"
    $sb = [Text.Encoding]::UTF8.GetString($b) -replace "`r`n", "`n"
    return ($sa -ne $sb)
}

# Compare bundle against what's installed. Returns New/Changed relative-path lists.
function Get-PendingChanges($src, $gameDir) {
    $new = New-Object System.Collections.Generic.List[string]
    $changed = New-Object System.Collections.Generic.List[string]
    foreach ($rel in Get-BundleFiles $src) {
        $dest = Join-Path $gameDir $rel
        if (-not (Test-Path $dest)) {
            $new.Add($rel)
        } elseif (Test-FileChanged (Join-Path $src $rel) $dest) {
            $changed.Add($rel)
        }
    }
    return [pscustomobject]@{ New = $new; Changed = $changed }
}

# Copy only the given relative paths from bundle into the game folder.
function Copy-BundleFiles($src, $gameDir, $relPaths) {
    foreach ($rel in $relPaths) {
        $dest = Join-Path $gameDir $rel
        $destDir = Split-Path $dest -Parent
        if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
        Copy-Item -Path (Join-Path $src $rel) -Destination $dest -Force
    }
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
    Write-Ok "Game folder: $GameDir"

    $alreadyInstalled = Test-ModsInstalled $GameDir
    if ($alreadyInstalled) { Write-Ok 'Mods already installed - checking for updates.' }
    else                   { Write-Ok 'Mods not detected - will perform a fresh install.' }

    # 2. Download the bundle from GitHub
    $work = Join-Path ([IO.Path]::GetTempPath()) ("pd2mods_" + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $work -Force | Out-Null
    $zip = Join-Path $work 'bundle.zip'

    Write-Step "Downloading latest mods from GitHub ($Repo)..."
    Invoke-WebRequest -Uri $ZipUrl -OutFile $zip -UseBasicParsing
    Write-Ok 'Download complete.'

    Write-Step 'Extracting...'
    Expand-Archive -Path $zip -DestinationPath $work -Force
    $extracted = Get-ChildItem -Path $work -Directory |
                 Where-Object { $_.Name -like 'pd2-mods-*' } |
                 Select-Object -First 1
    if (-not $extracted) { throw 'Extraction failed: source folder not found.' }
    $src = $extracted.FullName

    # 3. Compare against what's installed
    Write-Step 'Comparing with installed files...'
    $changes = Get-PendingChanges $src $GameDir
    $total = $changes.New.Count + $changes.Changed.Count

    if ($alreadyInstalled -and $total -eq 0) {
        Remove-Item -Path $work -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host ''
        Write-Host '  You already have the latest mods. Nothing to update.' -ForegroundColor Green
        Write-Host ''
        return
    }

    Write-Ok "$($changes.New.Count) new file(s), $($changes.Changed.Count) updated file(s)."
    foreach ($f in $changes.Changed) { Write-Host "      ~ $f" -ForegroundColor DarkYellow }
    foreach ($f in $changes.New)     { Write-Host "      + $f" -ForegroundColor DarkGreen }

    # 4. Confirm
    if (-not $Force) {
        $verb = if ($alreadyInstalled) { 'update' } else { 'install' }
        $ans = Read-Host "Apply these changes? [Y/n]"
        if ($ans -and $ans -notmatch '^(y|yes)$') {
            Remove-Item -Path $work -Recurse -Force -ErrorAction SilentlyContinue
            Write-Warn2 "Cancelled. Nothing was changed."
            return
        }
    }

    # 5. Apply
    Write-Step 'Installing files...'
    Copy-BundleFiles $src $GameDir ($changes.New + $changes.Changed)
    Write-Ok 'Files installed.'

    # 6. Clean up
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

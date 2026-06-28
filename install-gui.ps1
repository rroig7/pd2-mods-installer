<#
.SYNOPSIS
    GUI installer / updater for the pd2-mods bundle.
.DESCRIPTION
    A small WinForms window that auto-detects your PAYDAY 2 folder, downloads the
    latest mods from GitHub, and compares them with what's installed. It performs
    a fresh install when the mods are missing, or offers to update only the files
    that actually changed. Volatile user state (logs, saves, downloads) is never
    compared or overwritten. Compile to an .exe with build.ps1 (uses PS2EXE).
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# --- Config ------------------------------------------------------------------
$Repo    = 'rroig7/pd2-mods'
$Branch  = 'main'
$ZipUrl  = "https://github.com/$Repo/archive/refs/heads/$Branch.zip"
$AppId   = '218620'
$GameExe = 'payday2_win32_release.exe'

# Paths that are per-user runtime state: never compared, never overwritten.
$VolatilePrefixes = @('mods\logs\', 'mods\saves\', 'mods\downloads\')


# --- Detection (shared with install.ps1) ------------------------------------
function Get-SteamPath {
    foreach ($key in @('HKCU:\Software\Valve\Steam',
                       'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam',
                       'HKLM:\SOFTWARE\Valve\Steam')) {
        try {
            $item = Get-ItemProperty -Path $key -ErrorAction Stop
            $p = $item.SteamPath; if (-not $p) { $p = $item.InstallPath }
            if ($p -and (Test-Path $p)) { return (Resolve-Path $p).Path }
        } catch { }
    }
    return $null
}
function Get-SteamLibraries($steamPath) {
    $libs = New-Object System.Collections.Generic.List[string]
    if ($steamPath) { $libs.Add($steamPath) }
    $vdf = Join-Path $steamPath 'steamapps\libraryfolders.vdf'
    if (Test-Path $vdf) {
        foreach ($m in [regex]::Matches((Get-Content $vdf -Raw), '"path"\s*"([^"]+)"')) {
            $p = $m.Groups[1].Value -replace '\\\\', '\'
            if ((Test-Path $p) -and ($libs -notcontains $p)) { $libs.Add($p) }
        }
    }
    return $libs
}
function Find-Payday2 {
    $steam = Get-SteamPath
    $candidates = New-Object System.Collections.Generic.List[string]
    foreach ($lib in (Get-SteamLibraries $steam)) {
        $acf = Join-Path $lib "steamapps\appmanifest_$AppId.acf"
        if (Test-Path $acf) {
            $im = [regex]::Match((Get-Content $acf -Raw), '"installdir"\s*"([^"]+)"')
            if ($im.Success) { $candidates.Add((Join-Path $lib ("steamapps\common\" + $im.Groups[1].Value))) }
        }
        $candidates.Add((Join-Path $lib 'steamapps\common\PAYDAY 2'))
    }
    $candidates.Add('C:\Program Files (x86)\Steam\steamapps\common\PAYDAY 2')
    foreach ($c in $candidates) {
        if (Test-Path (Join-Path $c $GameExe)) { return (Resolve-Path $c).Path }
    }
    return $null
}

# --- Update detection (shared with install.ps1) -----------------------------
function Test-Volatile($rel) {
    foreach ($p in $VolatilePrefixes) { if ($rel -like "$p*") { return $true } }
    return $false
}
function Test-ModsInstalled($gameDir) {
    return (Test-Path (Join-Path $gameDir 'WSOCK32.dll')) -and
           (Test-Path (Join-Path $gameDir 'mods\base'))
}
function Get-BundleFiles($src) {
    $files = New-Object System.Collections.Generic.List[string]
    if (Test-Path (Join-Path $src 'WSOCK32.dll')) { $files.Add('WSOCK32.dll') }
    foreach ($f in Get-ChildItem (Join-Path $src 'mods') -Recurse -File) {
        $rel = $f.FullName.Substring($src.Length).TrimStart('\')
        if (-not (Test-Volatile $rel)) { $files.Add($rel) }
    }
    return $files
}
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
function Copy-BundleFiles($src, $gameDir, $relPaths) {
    foreach ($rel in $relPaths) {
        $dest = Join-Path $gameDir $rel
        $destDir = Split-Path $dest -Parent
        if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
        Copy-Item -Path (Join-Path $src $rel) -Destination $dest -Force
    }
}

# --- Build the window --------------------------------------------------------
$form = New-Object System.Windows.Forms.Form
$form.Text = 'PAYDAY 2 Mods Installer'
$form.Size = New-Object System.Drawing.Size(560, 420)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false

$title = New-Object System.Windows.Forms.Label
$title.Text = 'PAYDAY 2 Mods Installer'
$title.Font = New-Object System.Drawing.Font('Segoe UI', 14, [System.Drawing.FontStyle]::Bold)
$title.Location = New-Object System.Drawing.Point(15, 12)
$title.Size = New-Object System.Drawing.Size(520, 30)
$form.Controls.Add($title)

$lbl = New-Object System.Windows.Forms.Label
$lbl.Text = 'PAYDAY 2 install folder:'
$lbl.Location = New-Object System.Drawing.Point(15, 55)
$lbl.Size = New-Object System.Drawing.Size(520, 20)
$form.Controls.Add($lbl)

$pathBox = New-Object System.Windows.Forms.TextBox
$pathBox.Location = New-Object System.Drawing.Point(15, 78)
$pathBox.Size = New-Object System.Drawing.Size(420, 24)
$form.Controls.Add($pathBox)

$browse = New-Object System.Windows.Forms.Button
$browse.Text = 'Browse...'
$browse.Location = New-Object System.Drawing.Point(445, 77)
$browse.Size = New-Object System.Drawing.Size(90, 26)
$form.Controls.Add($browse)

$log = New-Object System.Windows.Forms.TextBox
$log.Multiline = $true
$log.ReadOnly = $true
$log.ScrollBars = 'Vertical'
$log.Location = New-Object System.Drawing.Point(15, 115)
$log.Size = New-Object System.Drawing.Size(520, 195)
$log.BackColor = [System.Drawing.Color]::White
$form.Controls.Add($log)

$progress = New-Object System.Windows.Forms.ProgressBar
$progress.Location = New-Object System.Drawing.Point(15, 320)
$progress.Size = New-Object System.Drawing.Size(520, 18)
$progress.Style = 'Continuous'
$form.Controls.Add($progress)

$install = New-Object System.Windows.Forms.Button
$install.Text = 'Install'
$install.Location = New-Object System.Drawing.Point(330, 345)
$install.Size = New-Object System.Drawing.Size(110, 30)
$form.Controls.Add($install)

$close = New-Object System.Windows.Forms.Button
$close.Text = 'Close'
$close.Location = New-Object System.Drawing.Point(445, 345)
$close.Size = New-Object System.Drawing.Size(90, 30)
$close.Add_Click({ $form.Close() })
$form.Controls.Add($close)

# --- Helpers -----------------------------------------------------------------
function Add-Log($msg) {
    $log.AppendText($msg + "`r`n")
    [System.Windows.Forms.Application]::DoEvents()
}

$browse.Add_Click({
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = 'Select your PAYDAY 2 folder'
    if ($pathBox.Text -and (Test-Path $pathBox.Text)) { $dlg.SelectedPath = $pathBox.Text }
    if ($dlg.ShowDialog() -eq 'OK') { $pathBox.Text = $dlg.SelectedPath }
})

$install.Add_Click({
    $install.Enabled = $false; $browse.Enabled = $false
    $progress.Value = 0
    $work = $null
    try {
        $gameDir = $pathBox.Text.Trim()
        if (-not (Test-Path (Join-Path $gameDir $GameExe))) {
            throw "That folder doesn't contain $GameExe."
        }
        [Net.ServicePointManager]::SecurityProtocol = `
            [Net.ServicePointManager]::SecurityProtocol -bor 3072

        $installed = Test-ModsInstalled $gameDir
        Add-Log $(if ($installed) { 'Mods already installed - checking for updates...' }
                  else            { 'Mods not detected - preparing a fresh install...' })

        $work = Join-Path ([IO.Path]::GetTempPath()) ("pd2mods_" + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $work -Force | Out-Null
        $zip = Join-Path $work 'bundle.zip'

        Add-Log "Downloading latest mods from GitHub ($Repo)..."
        Invoke-WebRequest -Uri $ZipUrl -OutFile $zip -UseBasicParsing
        $progress.Value = 50

        Add-Log 'Extracting...'
        Expand-Archive -Path $zip -DestinationPath $work -Force
        $src = (Get-ChildItem -Path $work -Directory | Where-Object { $_.Name -like 'pd2-mods-*' } | Select-Object -First 1).FullName
        if (-not $src) { throw 'Extraction failed.' }
        $progress.Value = 65

        Add-Log 'Comparing with installed files...'
        $changes = Get-PendingChanges $src $gameDir
        $total = $changes.New.Count + $changes.Changed.Count
        $progress.Value = 75

        if ($installed -and $total -eq 0) {
            $progress.Value = 100
            Add-Log 'You already have the latest mods. Nothing to update.'
            [System.Windows.Forms.MessageBox]::Show('You already have the latest mods.',
                'Up to date', 'OK', 'Information') | Out-Null
            return
        }

        Add-Log "$($changes.New.Count) new file(s), $($changes.Changed.Count) updated file(s)."
        foreach ($f in $changes.Changed) { Add-Log "  ~ $f" }
        foreach ($f in $changes.New)     { Add-Log "  + $f" }

        $summary = if ($installed) {
            "Updates are available:`n`n" +
            "$($changes.Changed.Count) file(s) changed`n$($changes.New.Count) new file(s)`n`nInstall them now?"
        } else {
            "$total file(s) will be installed.`n`nInstall the mods now?"
        }
        $title2 = if ($installed) { 'Update available' } else { 'Install mods' }
        $answer = [System.Windows.Forms.MessageBox]::Show($summary, $title2, 'YesNo', 'Question')
        if ($answer -ne 'Yes') {
            Add-Log 'Cancelled - no files were changed.'
            return
        }

        Add-Log 'Installing files...'
        Copy-BundleFiles $src $gameDir ($changes.New + $changes.Changed)
        $progress.Value = 100
        Add-Log ''
        Add-Log 'Done! Launch PAYDAY 2 through Steam to play with mods.'
        [System.Windows.Forms.MessageBox]::Show(
            $(if ($installed) { 'Mods updated successfully!' } else { 'Mods installed successfully!' }),
            'PAYDAY 2 Mods Installer', 'OK', 'Information') | Out-Null
    }
    catch {
        Add-Log "ERROR: $($_.Exception.Message)"
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Install failed',
            'OK', 'Error') | Out-Null
    }
    finally {
        if ($work) { Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue }
        $install.Enabled = $true; $browse.Enabled = $true
    }
})

# --- Init --------------------------------------------------------------------
$detected = Find-Payday2
if ($detected) {
    $pathBox.Text = $detected
    Add-Log "Auto-detected PAYDAY 2 at:`r`n$detected"
    if (Test-ModsInstalled $detected) {
        $install.Text = 'Check / Update'
        Add-Log 'Mods are already installed. Click "Check / Update" to compare with the latest.'
    } else {
        Add-Log 'Mods are not installed here yet. Click "Install" to set them up.'
    }
} else {
    Add-Log 'Could not auto-detect PAYDAY 2. Use Browse to pick the folder'
    Add-Log "(the one containing $GameExe)."
}

[void]$form.ShowDialog()

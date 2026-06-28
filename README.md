# PAYDAY 2 Mods Installer

A tiny Windows installer that sets up a [PAYDAY 2](https://store.steampowered.com/app/218620/)
mod bundle for you. It **auto-detects** your PAYDAY 2 install folder, downloads
the mods from GitHub, and copies them in — no manual file shuffling. Run it again
later and it **updates in place**, keeping your install in sync with GitHub.

The mods themselves live in a separate repo:
[**rroig7/pd2-mods**](https://github.com/rroig7/pd2-mods). This repo is just the
installer.

## Install

Pick whichever you prefer:

### Option 1 — Download the GUI (.exe)

1. Download [`PD2ModsInstaller.exe`](PD2ModsInstaller.exe).
2. Double-click it.
3. Confirm the detected PAYDAY 2 folder (or **Browse** to it), then click **Install**.

> Windows SmartScreen may warn about an unknown publisher (the exe is unsigned).
> Click **More info → Run anyway**.

### Option 2 — One-line PowerShell

Open PowerShell and paste:

```powershell
irm https://raw.githubusercontent.com/rroig7/pd2-mods-installer/main/install.ps1 | iex
```

### Option 3 — Double-click the .bat

Download [`install.bat`](install.bat) and run it (it just launches the
PowerShell installer above).

## What it installs

- `WSOCK32.dll` — the [SuperBLT](https://superblt.znix.xyz/) mod loader
- the `mods/` folder (SuperBLT base, BeardLib, WolfHUD, CustomFOV, and more)

See the [mods repo](https://github.com/rroig7/pd2-mods) for the full list and a
manual-install guide.

## Updating & removal sync

Run the installer again at any time to update. It compares your installed files
against the latest bundle on GitHub and only touches what actually differs:

- **New** files in the bundle are added.
- **Changed** files are overwritten (line-ending-only differences are ignored,
  so they aren't flagged as changes).
- **Removed** files — anything the bundle no longer contains is **deleted** from
  your install, and any folders left empty are pruned. This keeps your `mods/`
  folder matching GitHub **exactly**, so dropped mods don't linger.

Your own runtime state is never compared, overwritten, or deleted —
`mods/logs/`, `mods/saves/`, and `mods/downloads/` are always left alone, even
though they aren't part of the GitHub bundle.

If everything is already in sync, the installer tells you there's nothing to do.

## How auto-detection works

The installer reads your Steam path from the registry, walks every Steam library
listed in `libraryfolders.vdf`, and finds the folder containing
`payday2_win32_release.exe` (using `appmanifest_218620.acf` when present). If it
can't find the game, it asks you to point at the folder.

To target a specific folder manually:

```powershell
.\install.ps1 -GameDir "D:\Games\PAYDAY 2"
```

## Repo contents

| File | What it is |
| --- | --- |
| `PD2ModsInstaller.exe` | The prebuilt GUI installer |
| `install-gui.ps1` | Source for the GUI installer |
| `install.ps1` | Headless/CLI installer (the one the one-liner runs) |
| `install.bat` | Double-click launcher for `install.ps1` |
| `build.ps1` | Rebuilds the exe from `install-gui.ps1` using PS2EXE |

## Building the exe yourself

```powershell
.\build.ps1
```

This installs the [PS2EXE](https://github.com/MScholtes/PS2EXE) module (first run
only) and compiles `install-gui.ps1` into `PD2ModsInstaller.exe`.

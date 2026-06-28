@echo off
REM Double-click launcher for the PAYDAY 2 mods installer.
REM Runs install.ps1 from GitHub, bypassing PowerShell's execution policy.
echo Starting PAYDAY 2 Mods installer...
powershell -NoProfile -ExecutionPolicy Bypass -Command "iwr https://raw.githubusercontent.com/rroig7/pd2-mods-installer/main/install.ps1 -UseBasicParsing | iex"
echo.
pause

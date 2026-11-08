@echo off
rem Double-click to download every manual (PDF + EPUB) into a "downloads" folder next to this file.
rem Extra options can be passed through, e.g.:  Download.bat -Formats epub -Collection current
title T.REX Field Manual Vault downloader
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Get-FieldManuals.ps1" %*
echo.
pause

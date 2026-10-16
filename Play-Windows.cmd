@echo off
setlocal
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\play-windows.ps1"
if errorlevel 1 (
  echo.
  echo Neon Shard could not start. See the error above.
  pause
  exit /b 1
)

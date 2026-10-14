@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Start-Local.ps1" -RedeLocal
if errorlevel 1 (
  echo.
  echo Nao foi possivel iniciar a Biblioteca para a rede local.
  pause
)

@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Start-Local.ps1"
if errorlevel 1 (
  echo.
  echo A Biblioteca nao conseguiu iniciar. Leia a mensagem acima e consulte COMO-RODAR-EM-OUTRO-PC.md.
  pause
)
endlocal

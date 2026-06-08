@echo off
taskkill /f /im msedge.exe >nul 2>&1
taskkill /f /im MicrosoftEdgeUpdate.exe >nul 2>&1

set "E=%ProgramFiles(x86)%\Microsoft\Edge\Application"
if not exist "%E%" set "E=%ProgramFiles%\Microsoft\Edge\Application"

for /f "delims=" %%V in ('dir "%E%" /b /ad 2^>nul ^| findstr /r "^[0-9]"') do (
if exist "%E%\%%V\Installer\setup.exe" "%E%\%%V\Installer\setup.exe" --uninstall --system-level --force-uninstall >nul 2>&1
)

reg delete "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\msedge.exe" /f >nul 2>&1
reg delete "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\msedge.exe" /f >nul 2>&1
reg add "HKLM\SOFTWARE\Policies\Microsoft\EdgeUpdate" /v "InstallDefault" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Policies\Microsoft\EdgeUpdate" /v "AllowsAutoUpdate" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Policies\Microsoft\Edge" /v "HideFirstRunExperience" /t REG_DWORD /d 1 /f >nul 2>&1

powershell -NoProfile -Command "$ErrorActionPreference='SilentlyContinue'; Get-AppxPackage -AllUsers *MicrosoftEdge* | Where-Object {$_.Name -notmatch 'WebView'} | Remove-AppxPackage -AllUsers" >nul 2>&1

exit

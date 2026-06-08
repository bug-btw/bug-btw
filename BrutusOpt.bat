@echo off
setlocal enabledelayedexpansion

:: Elevacao de Privilegio
net session >nul 2>&1
if %errorlevel% neq 0 (
    PowerShell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

echo ============================================================
echo  BrutusOpt - Intelligent Optimization
echo ============================================================

:: ─── DNS ADGUARD (IPv4 & IPv6) ────────────────────────────────
echo [DNS] Aplicando DNS AdGuard...
for /f "tokens=3*" %%i in ('netsh interface show interface ^| findstr /i "connected"') do (
    netsh interface ipv4 set dns name="%%j" static 94.140.14.14 primary >nul 2>&1
    netsh interface ipv4 add dns name="%%j" addr=94.140.15.15 index=2 >nul 2>&1
    netsh interface ipv6 set dns name="%%j" static 2a10:50c0::ad1:ff primary >nul 2>&1
    netsh interface ipv6 add dns name="%%j" addr=2a10:50c0::ad2:ff index=2 >nul 2>&1
)
echo [DNS] Concluido.

:: ─── FLUSH DNS ────────────────────────────────────────────────
echo [REDE] Resetando configuracoes de rede...
ipconfig /flushdns >nul 2>&1
ipconfig /registerdns >nul 2>&1
netsh winsock reset >nul 2>&1
netsh int ip reset >nul 2>&1

:: ─── MEMORY & SYSMAIN ────────────────────────────────────────
PowerShell -NoProfile -Command "Disable-MMAgent -MemoryCompression -ErrorAction SilentlyContinue" >nul 2>&1
PowerShell -NoProfile -Command "Stop-Service SysMain -Force -ErrorAction SilentlyContinue; Set-Service SysMain -StartupType Disabled -ErrorAction SilentlyContinue" >nul 2>&1
echo [SISTEMA] Otimizacao de servicos concluida.

:: ─── POWER PLAN ──────────────────────────────────────────────
:: Duplicar plano de Alta Performance e renomear
for /f "tokens=4" %%G in ('powercfg /duplicatescheme 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c') do (
    set "BP_GUID=%%G"
)
powercfg /changename "%BP_GUID%" "Brutus OPT" >nul 2>&1
powercfg /setactive "%BP_GUID%" >nul 2>&1

:: Otimizacao focada no plano atual
for %%A in (PROCTHROTTLEMIN,PROCTHROTTLEMAX) do powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR %%A 100 >nul 2>&1
powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PERFBOOSTMODE 2 >nul 2>&1
powercfg /setacvalueindex SCHEME_CURRENT SUB_DISK DISKIDLE 0 >nul 2>&1
powercfg /setacvalueindex SCHEME_CURRENT SUB_PCIEXPRESS ASPM 0 >nul 2>&1
powercfg /setactive SCHEME_CURRENT >nul 2>&1
echo [POWER] Plano Brutus OPT ativado.

:: ─── LIMPEZA GERAL (Temp / Prefetch / Cache) ──────────────────
del /f /s /q "%temp%\*.*" >nul 2>&1
for /d %%d in ("%temp%\*") do rd /s /q "%%d" >nul 2>&1
del /f /s /q "C:\Windows\Temp\*.*" >nul 2>&1
del /f /q "C:\Windows\Prefetch\*.pf" >nul 2>&1
PowerShell -NoProfile -Command "Clear-RecycleBin -Force -ErrorAction SilentlyContinue" >nul 2>&1
echo [LIMPEZA] Arquivos temporarios removidos.

:: ─── TELEMETRIA E GAME DVR ──────────────────────────────────
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection" /v AllowTelemetry /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKCU\System\GameConfigStore" /v GameDVR_Enabled /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\GameDVR" /v AllowGameDVR /t REG_DWORD /d 0 /f >nul 2>&1

echo.
echo ============================================================
echo  Otimizacao finalizada. Recomendado reiniciar o sistema.
echo ============================================================
echo.
pause

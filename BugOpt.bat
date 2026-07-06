@echo off
setlocal enabledelayedexpansion

net session >nul 2>&1
if %errorlevel% neq 0 (
    PowerShell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

echo ============================================================
echo  BrutusOpt - Otimizacao Inteligente
echo ============================================================
echo.

:: ─── DNS ──────────────────────────────────────────────────────────────────────
set "DNS4_P=94.140.14.14"
set "DNS4_S=94.140.15.15"
set "DNS6_P=2a10:50c0::ad1:ff"
set "DNS6_S=2a10:50c0::ad2:ff"

set "DNS_NEED=0"
for /f "tokens=3*" %%i in ('netsh interface show interface ^| findstr /i "connected"') do (
    set "HAS4=" & set "HAS6="
    for /f "tokens=*" %%D in ('netsh interface ipv4 show dns name="%%j" 2^>nul') do (
        echo %%D | findstr /i "!DNS4_P!" >nul 2>&1 && set "HAS4=1"
    )
    for /f "tokens=*" %%D in ('netsh interface ipv6 show dns name="%%j" 2^>nul') do (
        echo %%D | findstr /i "ad1" >nul 2>&1 && set "HAS6=1"
    )
    if not defined HAS4 set "DNS_NEED=1"
    if not defined HAS6 set "DNS_NEED=1"
)
if "!DNS_NEED!"=="1" (
    echo [DNS] Aplicando DNS AdGuard IPv4 e IPv6...
    for /f "tokens=3*" %%i in ('netsh interface show interface ^| findstr /i "connected"') do (
        netsh interface ipv4 set dns name="%%j" static !DNS4_P! primary validate=no >nul 2>&1
        netsh interface ipv4 add dns name="%%j" addr=!DNS4_S! index=2 validate=no >nul 2>&1
        netsh interface ipv6 set dns name="%%j" static !DNS6_P! validate=no >nul 2>&1
        netsh interface ipv6 add dns name="%%j" addr=!DNS6_S! index=2 validate=no >nul 2>&1
    )
    echo [DNS] Concluido.
) else (
    echo [DNS] Ja configurado. Ignorando.
)

:: ─── FLUSH DNS ────────────────────────────────────────────────────────────────
set "DNS_ENTRIES=0"
for /f %%C in ('PowerShell -NoProfile -Command "try{(Get-DnsClientCache).Count}catch{0}"') do set "DNS_ENTRIES=%%C"
if !DNS_ENTRIES! gtr 0 (
    echo [REDE] Cache DNS com !DNS_ENTRIES! entradas. Limpando...
    ipconfig /flushdns >nul 2>&1
    ipconfig /registerdns >nul 2>&1
    echo [REDE] Concluido.
) else (
    echo [REDE] Cache DNS ja limpo. Ignorando.
)

:: ─── MEMORY COMPRESSION ───────────────────────────────────────────────────────
set "MEMCOMP=False"
for /f %%M in ('PowerShell -NoProfile -Command "try{(Get-MMAgent).MemoryCompression}catch{'False'}"') do set "MEMCOMP=%%M"
if /i "!MEMCOMP!"=="True" (
    echo [MEM] Desabilitando Memory Compression...
    PowerShell -NoProfile -Command "Disable-MMAgent -MemoryCompression" >nul 2>&1
    echo [MEM] Concluido.
) else (
    echo [MEM] Memory Compression ja desabilitada. Ignorando.
)

:: ─── SUPERFETCH / SYSMAIN ─────────────────────────────────────────────────────
set "SYSMAIN=NotFound"
for /f %%S in ('PowerShell -NoProfile -Command "try{(Get-Service SysMain -ErrorAction Stop).Status}catch{'NotFound'}"') do set "SYSMAIN=%%S"
if /i "!SYSMAIN!"=="Running" (
    echo [SYSMAIN] Desabilitando SysMain...
    PowerShell -NoProfile -Command "Stop-Service SysMain -Force -ErrorAction SilentlyContinue; Set-Service SysMain -StartupType Disabled -ErrorAction SilentlyContinue" >nul 2>&1
    echo [SYSMAIN] Concluido.
) else (
    echo [SYSMAIN] SysMain ja desabilitado. Ignorando.
)

:: ─── POWER PLAN BRUTUS OPT ────────────────────────────────────────────────────
set "BRUTUS_GUID="
set "ULT_GUID=e9a42b02-d5df-448d-aa00-03f14749eb61"

for /f "tokens=4" %%G in ('powercfg /list 2^>nul ^| findstr /i "Brutus OPT"') do set "BRUTUS_GUID=%%G"

if not defined BRUTUS_GUID (
    echo [POWER] Criando plano Brutus OPT...
    set "NEW_GUID="
    for /f "tokens=4" %%G in ('powercfg /duplicatescheme !ULT_GUID! 2^>nul') do set "NEW_GUID=%%G"
    if not defined NEW_GUID (
        for /f "tokens=4" %%G in ('powercfg /list 2^>nul ^| findstr /i "Ultimate Performance"') do set "NEW_GUID=%%G"
    )
    if not defined NEW_GUID (
        for /f "tokens=4" %%G in ('powercfg /list 2^>nul ^| findstr /i "High performance"') do set "NEW_GUID=%%G"
    )
    if not defined NEW_GUID (
        echo [POWER] Falha: nenhum plano base disponivel.
        goto :POWER_END
    )
    set "BRUTUS_GUID=!NEW_GUID!"
    powercfg /changename "!BRUTUS_GUID!" "Brutus OPT" "Performance absoluta - BrutusOpt" >nul 2>&1
    echo [POWER] Plano Brutus OPT criado.
) else (
    echo [POWER] Plano Brutus OPT ja existe. Verificando estado...
)

for /f "tokens=4" %%G in ('powercfg /getactivescheme 2^>nul') do set "ACTIVE_GUID=%%G"
if /i "!ACTIVE_GUID!" neq "!BRUTUS_GUID!" (
    powercfg /setactive "!BRUTUS_GUID!" >nul 2>&1
    echo [POWER] Plano ativado.
) else (
    echo [POWER] Plano ja ativo.
)

for %%A in (ac dc) do (
    powercfg /set%%Avalueindex "!BRUTUS_GUID!" SUB_PROCESSOR PROCTHROTTLEMIN 100 >nul 2>&1
    powercfg /set%%Avalueindex "!BRUTUS_GUID!" SUB_PROCESSOR PROCTHROTTLEMAX 100 >nul 2>&1
    powercfg /set%%Avalueindex "!BRUTUS_GUID!" SUB_PROCESSOR PERFBOOSTMODE 2 >nul 2>&1
    powercfg /set%%Avalueindex "!BRUTUS_GUID!" SUB_PROCESSOR PERFBOOSTPOL 100 >nul 2>&1
    powercfg /set%%Avalueindex "!BRUTUS_GUID!" SUB_SLEEP STANDBYIDLE 0 >nul 2>&1
    powercfg /set%%Avalueindex "!BRUTUS_GUID!" SUB_SLEEP HIBERNATEIDLE 0 >nul 2>&1
    powercfg /set%%Avalueindex "!BRUTUS_GUID!" SUB_VIDEO VIDEOIDLE 0 >nul 2>&1
    powercfg /set%%Avalueindex "!BRUTUS_GUID!" SUB_DISK DISKIDLE 0 >nul 2>&1
    powercfg /set%%Avalueindex "!BRUTUS_GUID!" SUB_PCIEXPRESS ASPM 0 >nul 2>&1
)
powercfg /setacvalueindex "!BRUTUS_GUID!" SUB_PROCESSOR PERFINCPOL 2 >nul 2>&1
powercfg /setacvalueindex "!BRUTUS_GUID!" SUB_PROCESSOR PERFDECPOL 1 >nul 2>&1
powercfg /setacvalueindex "!BRUTUS_GUID!" SUB_PROCESSOR PERFINCTHRESHOLD 10 >nul 2>&1
powercfg /setacvalueindex "!BRUTUS_GUID!" SUB_PROCESSOR PERFDECTHRESHOLD 8 >nul 2>&1
powercfg /setacvalueindex "!BRUTUS_GUID!" SUB_PROCESSOR CPHEADROOM 0 >nul 2>&1
powercfg /setacvalueindex "!BRUTUS_GUID!" SUB_PROCESSOR LATENCYHINTPERF 100 >nul 2>&1
powercfg /setacvalueindex "!BRUTUS_GUID!" SUB_SLEEP HYBRIDSLEEP 0 >nul 2>&1
powercfg /setacvalueindex "!BRUTUS_GUID!" SUB_SLEEP RTCWAKE 0 >nul 2>&1
powercfg /setacvalueindex "!BRUTUS_GUID!" SUB_VIDEO ADAPTBRIGHT 0 >nul 2>&1
powercfg /setacvalueindex "!BRUTUS_GUID!" SUB_DISK DISKBURST 1 >nul 2>&1
powercfg /setacvalueindex "!BRUTUS_GUID!" SUB_NONE CONNECTIVITYINSTANDBY 0 >nul 2>&1

set "OTHER_PLANS=0"
for /f "tokens=4" %%G in ('powercfg /list 2^>nul ^| findstr /i "Power Scheme GUID"') do (
    if /i "%%G" neq "!BRUTUS_GUID!" set "OTHER_PLANS=1"
)
if "!OTHER_PLANS!"=="1" (
    echo [POWER] Outros planos detectados. Removendo...
    for /f "tokens=4" %%G in ('powercfg /list 2^>nul ^| findstr /i "Power Scheme GUID"') do (
        if /i "%%G" neq "!BRUTUS_GUID!" powercfg /delete "%%G" >nul 2>&1
    )
    echo [POWER] Planos removidos.
) else (
    echo [POWER] Nenhum outro plano. Ignorando.
)
echo [POWER] Brutus OPT ativo e configurado.
:POWER_END

:: ─── VISUAL EFFECTS ───────────────────────────────────────────────────────────
set "VFX=-1" & set "ICONS=-1" & set "FONTS=-1"
for /f %%V in ('PowerShell -NoProfile -Command "try{(Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects').VisualFXSetting}catch{-1}"') do set "VFX=%%V"
for /f %%I in ('PowerShell -NoProfile -Command "try{(Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced').IconsOnly}catch{-1}"') do set "ICONS=%%I"
for /f %%F in ('PowerShell -NoProfile -Command "try{(Get-ItemProperty 'HKCU:\Control Panel\Desktop').FontSmoothing}catch{-1}"') do set "FONTS=%%F"
if "!VFX!"=="3" if "!ICONS!"=="0" if "!FONTS!"=="2" (
    echo [VISUAL] Efeitos visuais ja configurados. Ignorando.
    goto :VISUAL_END
)
echo [VISUAL] Aplicando configuracao custom de efeitos visuais...
PowerShell -NoProfile -Command ^
    "$vfx='HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects';" ^
    "$adv='HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced';" ^
    "$desk='HKCU:\Control Panel\Desktop';" ^
    "$wm='HKCU:\Control Panel\Desktop\WindowMetrics';" ^
    "Set-ItemProperty -Path $vfx -Name VisualFXSetting -Value 3 -Force;" ^
    "Set-ItemProperty -Path $desk -Name UserPreferencesMask -Value ([byte[]](0x90,0x12,0x03,0x80,0x10,0x00,0x00,0x00)) -Force;" ^
    "Set-ItemProperty -Path $desk -Name FontSmoothing -Value '2' -Force;" ^
    "Set-ItemProperty -Path $desk -Name FontSmoothingType -Value 2 -Force;" ^
    "Set-ItemProperty -Path $desk -Name FontSmoothingGamma -Value 1450 -Force;" ^
    "Set-ItemProperty -Path $desk -Name DragFullWindows -Value '0' -Force;" ^
    "if(-not(Test-Path $wm)){New-Item -Path $wm -Force|Out-Null};" ^
    "Set-ItemProperty -Path $wm -Name MinAnimate -Value '0' -Force;" ^
    "Set-ItemProperty -Path $adv -Name IconsOnly -Value 0 -Force;" ^
    "Set-ItemProperty -Path $adv -Name TaskbarAnimations -Value 0 -Force;" ^
    "Set-ItemProperty -Path $adv -Name EnableAeroPeek -Value 0 -Force;" ^
    "Set-ItemProperty -Path $adv -Name ListviewShadow -Value 0 -Force;" ^
    "Set-ItemProperty -Path $adv -Name ListviewAlphaSelect -Value 0 -Force;" ^
    "Set-ItemProperty -Path $adv -Name ExtendedUIHoverTime -Value 0 -Force" >nul 2>&1
echo [VISUAL] Concluido.
:VISUAL_END

:: ─── TEMP DO USUARIO ──────────────────────────────────────────────────────────
set "TMP_COUNT=0"
if exist "%temp%\" (
    for /f %%F in ('dir /b /a "%temp%" 2^>nul ^| find /c /v ""') do set "TMP_COUNT=%%F"
)
if !TMP_COUNT! gtr 0 (
    echo [TMP] !TMP_COUNT! itens em Temp usuario. Limpando...
    for /d %%D in ("%temp%\*") do rd /s /q "%%D" >nul 2>&1
    for %%F in ("%temp%\*") do del /f /q "%%F" >nul 2>&1
    echo [TMP] Concluido.
) else (
    echo [TMP] Temp usuario ja vazia. Ignorando.
)

:: ─── TEMP DO WINDOWS ──────────────────────────────────────────────────────────
set "TMPW_COUNT=0"
if exist "C:\Windows\Temp\" (
    for /f %%F in ('dir /b /a "C:\Windows\Temp" 2^>nul ^| find /c /v ""') do set "TMPW_COUNT=%%F"
)
if !TMPW_COUNT! gtr 0 (
    echo [TMPW] !TMPW_COUNT! itens em Windows Temp. Limpando...
    for /d %%D in ("C:\Windows\Temp\*") do rd /s /q "%%D" >nul 2>&1
    for %%F in ("C:\Windows\Temp\*") do del /f /q "%%F" >nul 2>&1
    if not exist "C:\Windows\Temp\" mkdir "C:\Windows\Temp" >nul 2>&1
    echo [TMPW] Concluido.
) else (
    echo [TMPW] Windows Temp ja vazia. Ignorando.
)

:: ─── PREFETCH ─────────────────────────────────────────────────────────────────
set "PRE_COUNT=0"
if exist "C:\Windows\Prefetch\" (
    for /f %%F in ('dir /b /a "C:\Windows\Prefetch\*.pf" 2^>nul ^| find /c /v ""') do set "PRE_COUNT=%%F"
)
if !PRE_COUNT! gtr 0 (
    echo [PRE] !PRE_COUNT! arquivos em Prefetch. Limpando...
    del /f /s /q "C:\Windows\Prefetch\*.pf" >nul 2>&1
    echo [PRE] Concluido.
) else (
    echo [PRE] Prefetch ja vazio. Ignorando.
)

:: ─── CACHE DO SISTEMA ─────────────────────────────────────────────────────────
set "CACHE_LIMPO=1"
for %%D in (
    "%LOCALAPPDATA%\Microsoft\Windows\INetCache"
    "%LOCALAPPDATA%\Temp"
    "%APPDATA%\Microsoft\Windows\Recent"
) do (
    if exist "%%~D\" (
        for /f %%F in ('dir /b /a "%%~D" 2^>nul ^| find /c /v ""') do if %%F gtr 0 set "CACHE_LIMPO=0"
    )
)
if "!CACHE_LIMPO!"=="0" (
    echo [CACHE] Limpando caches do sistema...
    for %%D in (
        "%LOCALAPPDATA%\Microsoft\Windows\INetCache"
        "%LOCALAPPDATA%\Temp"
        "%APPDATA%\Microsoft\Windows\Recent"
    ) do (
        if exist "%%~D\" (
            for /d %%X in ("%%~D\*") do rd /s /q "%%X" >nul 2>&1
            for %%X in ("%%~D\*") do del /f /q "%%X" >nul 2>&1
        )
    )
    echo [CACHE] Concluido.
) else (
    echo [CACHE] Todos os caches ja limpos. Ignorando.
)

:: ─── LIXEIRA ──────────────────────────────────────────────────────────────────
set "RECYCLE=0"
for /f %%R in ('PowerShell -NoProfile -Command "try{(New-Object -ComObject Shell.Application).NameSpace(10).Items().Count}catch{0}"') do set "RECYCLE=%%R"
if !RECYCLE! gtr 0 (
    echo [LIXEIRA] !RECYCLE! itens na Lixeira. Esvaziando...
    PowerShell -NoProfile -Command "Clear-RecycleBin -Force -ErrorAction SilentlyContinue" >nul 2>&1
    echo [LIXEIRA] Concluido.
) else (
    echo [LIXEIRA] Lixeira ja vazia. Ignorando.
)

:: ─── WINDOWS UPDATE CACHE ─────────────────────────────────────────────────────
set "WU_COUNT=0"
if exist "C:\Windows\SoftwareDistribution\Download\" (
    for /f %%F in ('dir /b /a "C:\Windows\SoftwareDistribution\Download" 2^>nul ^| find /c /v ""') do set "WU_COUNT=%%F"
)
if !WU_COUNT! gtr 0 (
    echo [WU] !WU_COUNT! itens em cache Windows Update. Limpando...
    net stop wuauserv /y >nul 2>&1
    net stop bits /y >nul 2>&1
    rd /s /q "C:\Windows\SoftwareDistribution\Download" >nul 2>&1
    mkdir "C:\Windows\SoftwareDistribution\Download" >nul 2>&1
    net start bits >nul 2>&1
    net start wuauserv >nul 2>&1
    echo [WU] Concluido.
) else (
    echo [WU] Cache Windows Update ja limpo. Ignorando.
)

:: ─── TRIM SSD ─────────────────────────────────────────────────────────────────
set "SSD_COUNT=0"
for /f %%T in ('PowerShell -NoProfile -Command "try{@(Get-PhysicalDisk|Where-Object{$_.MediaType -eq 'SSD'}).Count}catch{0}"') do set "SSD_COUNT=%%T"
if !SSD_COUNT! gtr 0 (
    echo [TRIM] !SSD_COUNT! SSD(s) detectado(s). Executando TRIM...
    PowerShell -NoProfile -Command "try{Get-PhysicalDisk|Where-Object{$_.MediaType -eq 'SSD'}|ForEach-Object{$n=$_.DeviceId;Get-Partition -DiskNumber $n -ErrorAction SilentlyContinue|Where-Object{$_.DriveLetter}|ForEach-Object{Optimize-Volume -DriveLetter $_.DriveLetter -ReTrim -ErrorAction SilentlyContinue}}}catch{}" >nul 2>&1
    echo [TRIM] Concluido.
) else (
    echo [TRIM] Nenhum SSD detectado. Ignorando.
)

:: ─── SERVICOS DESNECESSARIOS ──────────────────────────────────────────────────
set "SVC_CHANGED=0"
for %%S in (DiagTrack WMPNetworkSvc XblAuthManager XblGameSave XboxNetApiSvc lfsvc MapsBroker RetailDemo WerSvc) do (
    set "SVC_TYPE=NotFound"
    for /f %%T in ('PowerShell -NoProfile -Command "try{(Get-Service -Name '%%S' -ErrorAction Stop).StartType}catch{'NotFound'}"') do set "SVC_TYPE=%%T"
    if /i "!SVC_TYPE!" neq "Disabled" if /i "!SVC_TYPE!" neq "NotFound" (
        PowerShell -NoProfile -Command "try{Stop-Service -Name '%%S' -Force -ErrorAction SilentlyContinue;Set-Service -Name '%%S' -StartupType Disabled -ErrorAction SilentlyContinue}catch{}" >nul 2>&1
        set "SVC_CHANGED=1"
    )
)
if "!SVC_CHANGED!"=="1" (
    echo [SERVICOS] Servicos desnecessarios desabilitados.
) else (
    echo [SERVICOS] Todos os servicos ja desabilitados. Ignorando.
)

:: ─── TELEMETRIA ───────────────────────────────────────────────────────────────
set "TEL_OK=0"
for /f "tokens=3" %%T in ('reg query "HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection" /v AllowTelemetry 2^>nul') do if "%%T"=="0x0" set "TEL_OK=1"
if "!TEL_OK!"=="0" (
    echo [TELEMETRIA] Desabilitando telemetria...
    reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection" /v AllowTelemetry /t REG_DWORD /d 0 /f >nul 2>&1
    reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection" /v AllowTelemetry /t REG_DWORD /d 0 /f >nul 2>&1
    PowerShell -NoProfile -Command ^
        "Disable-ScheduledTask -TaskPath '\Microsoft\Windows\Application Experience\' -TaskName 'Microsoft Compatibility Appraiser' -ErrorAction SilentlyContinue;" ^
        "Disable-ScheduledTask -TaskPath '\Microsoft\Windows\Application Experience\' -TaskName 'ProgramDataUpdater' -ErrorAction SilentlyContinue;" ^
        "Disable-ScheduledTask -TaskPath '\Microsoft\Windows\Customer Experience Improvement Program\' -TaskName 'Consolidator' -ErrorAction SilentlyContinue" >nul 2>&1
    echo [TELEMETRIA] Concluido.
) else (
    echo [TELEMETRIA] Telemetria ja desabilitada. Ignorando.
)

:: ─── GAME MODE / GAME DVR ─────────────────────────────────────────────────────
set "GMODE=" & set "GDVR="
for /f "tokens=3" %%G in ('reg query "HKCU\SOFTWARE\Microsoft\GameBar" /v AutoGameModeEnabled 2^>nul') do if "%%G"=="0x1" set "GMODE=1"
for /f "tokens=3" %%G in ('reg query "HKCU\System\GameConfigStore" /v GameDVR_Enabled 2^>nul') do if "%%G"=="0x0" set "GDVR=1"
if not defined GMODE (
    echo [GAME] Configurando Game Mode e desabilitando DVR...
    reg add "HKCU\SOFTWARE\Microsoft\GameBar" /v AllowAutoGameMode /t REG_DWORD /d 1 /f >nul 2>&1
    reg add "HKCU\SOFTWARE\Microsoft\GameBar" /v AutoGameModeEnabled /t REG_DWORD /d 1 /f >nul 2>&1
    reg add "HKCU\System\GameConfigStore" /v GameDVR_Enabled /t REG_DWORD /d 0 /f >nul 2>&1
    reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\GameDVR" /v AllowGameDVR /t REG_DWORD /d 0 /f >nul 2>&1
    echo [GAME] Concluido.
) else if not defined GDVR (
    echo [GAME] Desabilitando Game DVR...
    reg add "HKCU\System\GameConfigStore" /v GameDVR_Enabled /t REG_DWORD /d 0 /f >nul 2>&1
    reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\GameDVR" /v AllowGameDVR /t REG_DWORD /d 0 /f >nul 2>&1
    echo [GAME] Concluido.
) else (
    echo [GAME] Game Mode ja configurado. Ignorando.
)

:: ─── PAGINACAO / VIRTUAL MEMORY ───────────────────────────────────────────────
set "RAM_GB=0"
for /f %%R in ('PowerShell -NoProfile -Command "try{[math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory/1GB)}catch{0}"') do set "RAM_GB=%%R"
if !RAM_GB! geq 16 (
    set "AUTO_PF=True" & set "PF_INIT=-1"
    for /f %%A in ('PowerShell -NoProfile -Command "try{(Get-CimInstance Win32_ComputerSystem).AutomaticManagedPagefile}catch{'True'}"') do set "AUTO_PF=%%A"
    for /f %%P in ('PowerShell -NoProfile -Command "try{$p=Get-WmiObject Win32_PageFileSetting;if($p){$p.InitialSize}else{-1}}catch{-1}"') do set "PF_INIT=%%P"
    if /i "!AUTO_PF!"=="True" (
        echo [PAGE] RAM !RAM_GB!GB - Desativando paginacao automatica e fixando tamanho...
        PowerShell -NoProfile -Command "$cs=Get-WmiObject Win32_ComputerSystem -EnableAllPrivileges;$cs.AutomaticManagedPagefile=$false;$cs.Put()|Out-Null;$pf=Get-WmiObject Win32_PageFileSetting;if($pf){$pf.InitialSize=2048;$pf.MaximumSize=4096;$pf.Put()|Out-Null}else{Set-WmiInstance -Class Win32_PageFileSetting -Arguments @{Name='C:\pagefile.sys';InitialSize=2048;MaximumSize=4096}|Out-Null}" >nul 2>&1
        echo [PAGE] Concluido.
    ) else if "!PF_INIT!" neq "2048" (
        echo [PAGE] RAM !RAM_GB!GB - Ajustando tamanho de paginacao...
        PowerShell -NoProfile -Command "$pf=Get-WmiObject Win32_PageFileSetting;if($pf){$pf.InitialSize=2048;$pf.MaximumSize=4096;$pf.Put()|Out-Null}" >nul 2>&1
        echo [PAGE] Concluido.
    ) else (
        echo [PAGE] Paginacao ja otimizada. Ignorando.
    )
) else (
    echo [PAGE] RAM !RAM_GB!GB. Mantendo paginacao automatica.
)

echo.
echo ============================================================
echo  Otimizacao finalizada com sucesso.
echo ============================================================
echo.
exit /b 0

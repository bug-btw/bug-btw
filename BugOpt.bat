@echo off
setlocal enabledelayedexpansion

net session >nul 2>&1
if %errorlevel% neq 0 (
    PowerShell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

echo ============================================================
echo  BugOpt - Otimizacao Inteligente
echo ============================================================
echo.

:: --- DNS ----------------------------------------------------------------------
set "DNS4_P=94.140.14.14"
set "DNS4_S=94.140.15.15"
set "DNS6_P=2a10:50c0::ad1:ff"
set "DNS6_S=2a10:50c0::ad2:ff"

set "DNS_NEED=0"
set "IFACE_LIST_PS=%TEMP%\BugOpt_Ifaces.ps1"
set "IFACE_LOG=%TEMP%\BugOpt_Ifaces.log"
if exist "!IFACE_LIST_PS!" del /f /q "!IFACE_LIST_PS!" >nul 2>&1
if exist "!IFACE_LOG!" del /f /q "!IFACE_LOG!" >nul 2>&1

(
echo $ErrorActionPreference = 'SilentlyContinue'
echo Get-NetAdapter ^| Where-Object { $_.Status -eq 'Up' } ^| ForEach-Object { Write-Output $_.Name }
) > "!IFACE_LIST_PS!"

PowerShell -NoProfile -ExecutionPolicy Bypass -File "!IFACE_LIST_PS!" > "!IFACE_LOG!" 2>nul
del /f /q "!IFACE_LIST_PS!" >nul 2>&1

if exist "!IFACE_LOG!" (
    for /f "usebackq delims=" %%J in ("!IFACE_LOG!") do (
        set "HAS4=" & set "HAS6="
        for /f "delims=" %%D in ('netsh interface ipv4 show dns name="%%J" 2^>nul ^| findstr /i "!DNS4_P!"') do set "HAS4=1"
        for /f "delims=" %%D in ('netsh interface ipv6 show dns name="%%J" 2^>nul ^| findstr /i "!DNS6_P!"') do set "HAS6=1"
        if not defined HAS4 set "DNS_NEED=1"
        if not defined HAS6 set "DNS_NEED=1"
    )
) else (
    set "DNS_NEED=1"
)

if "!DNS_NEED!"=="1" (
    echo [DNS] Aplicando DNS AdGuard IPv4 e IPv6...
    if exist "!IFACE_LOG!" (
        for /f "usebackq delims=" %%J in ("!IFACE_LOG!") do (
            netsh interface ipv4 set dns name="%%J" static !DNS4_P! primary validate=no >nul 2>&1
            netsh interface ipv4 add dns name="%%J" addr=!DNS4_S! index=2 validate=no >nul 2>&1
            netsh interface ipv6 set dns name="%%J" static !DNS6_P! validate=no >nul 2>&1
            netsh interface ipv6 add dns name="%%J" addr=!DNS6_S! index=2 validate=no >nul 2>&1
        )
    )
    echo [DNS] Concluido.
) else (
    echo [DNS] Ja configurado. Ignorando.
)
if exist "!IFACE_LOG!" del /f /q "!IFACE_LOG!" >nul 2>&1

:: --- FLUSH DNS ----------------------------------------------------------------
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

:: --- MEMORY COMPRESSION -------------------------------------------------------
set "MEMCOMP=False"
for /f %%M in ('PowerShell -NoProfile -Command "try{(Get-MMAgent).MemoryCompression}catch{'False'}"') do set "MEMCOMP=%%M"
if /i "!MEMCOMP!"=="True" (
    echo [MEM] Desabilitando Memory Compression...
    PowerShell -NoProfile -Command "Disable-MMAgent -MemoryCompression" >nul 2>&1
    echo [MEM] Concluido.
) else (
    echo [MEM] Memory Compression ja desabilitada. Ignorando.
)

:: --- SUPERFETCH / SYSMAIN -----------------------------------------------------
set "SYSMAIN=NotFound"
set "SYSMAIN_START=NotFound"
for /f %%S in ('PowerShell -NoProfile -Command "try{(Get-Service SysMain -ErrorAction Stop).Status}catch{'NotFound'}"') do set "SYSMAIN=%%S"
for /f %%S in ('PowerShell -NoProfile -Command "try{(Get-Service SysMain -ErrorAction Stop).StartType}catch{'NotFound'}"') do set "SYSMAIN_START=%%S"
if /i "!SYSMAIN!"=="Running" (
    echo [SYSMAIN] Desabilitando SysMain...
    PowerShell -NoProfile -Command "Stop-Service SysMain -Force -ErrorAction SilentlyContinue; Set-Service SysMain -StartupType Disabled -ErrorAction SilentlyContinue" >nul 2>&1
    echo [SYSMAIN] Concluido.
) else if /i "!SYSMAIN_START!" neq "Disabled" if /i "!SYSMAIN_START!" neq "NotFound" (
    echo [SYSMAIN] Servico parado mas nao desabilitado. Corrigindo StartType...
    PowerShell -NoProfile -Command "Set-Service SysMain -StartupType Disabled -ErrorAction SilentlyContinue" >nul 2>&1
    echo [SYSMAIN] Concluido.
) else (
    echo [SYSMAIN] SysMain ja desabilitado. Ignorando.
)

:: --- POWER PLAN BUG OPT ----------------------------------------------------
set "BUG_GUID="
set "ULT_GUID=e9a42b02-d5df-448d-aa00-03f14749eb61"
set "POWER_FAIL=0"

for /f "tokens=4" %%G in ('powercfg /list 2^>nul ^| findstr /i "Bug OPT"') do set "BUG_GUID=%%G"

if not defined BUG_GUID (
    echo [POWER] Criando plano Bug OPT...
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
        set "POWER_FAIL=1"
    ) else (
        set "BUG_GUID=!NEW_GUID!"
        powercfg /changename "!BUG_GUID!" "Bug OPT" "Performance absoluta - BugOpt" >nul 2>&1
        echo [POWER] Plano Bug OPT criado.
    )
) else (
    echo [POWER] Plano Bug OPT ja existe. Verificando estado...
)

if "!POWER_FAIL!"=="0" (
    set "ACTIVE_GUID="
    for /f "tokens=4" %%G in ('powercfg /getactivescheme 2^>nul') do set "ACTIVE_GUID=%%G"
    if not defined ACTIVE_GUID (
        echo [POWER] Nao foi possivel ler o plano ativo. Ativando Bug OPT por seguranca...
        powercfg /setactive "!BUG_GUID!" >nul 2>&1
    ) else if /i "!ACTIVE_GUID!" neq "!BUG_GUID!" (
        powercfg /setactive "!BUG_GUID!" >nul 2>&1
        echo [POWER] Plano ativado.
    ) else (
        echo [POWER] Plano ja ativo.
    )

    for %%A in (ac dc) do (
        powercfg /set%%Avalueindex "!BUG_GUID!" SUB_PROCESSOR PROCTHROTTLEMIN 100 >nul 2>&1
        powercfg /set%%Avalueindex "!BUG_GUID!" SUB_PROCESSOR PROCTHROTTLEMAX 100 >nul 2>&1
        powercfg /set%%Avalueindex "!BUG_GUID!" SUB_PROCESSOR PERFBOOSTMODE 2 >nul 2>&1
        powercfg /set%%Avalueindex "!BUG_GUID!" SUB_PROCESSOR PERFBOOSTPOL 100 >nul 2>&1
        powercfg /set%%Avalueindex "!BUG_GUID!" SUB_SLEEP STANDBYIDLE 0 >nul 2>&1
        powercfg /set%%Avalueindex "!BUG_GUID!" SUB_SLEEP HIBERNATEIDLE 0 >nul 2>&1
        powercfg /set%%Avalueindex "!BUG_GUID!" SUB_VIDEO VIDEOIDLE 0 >nul 2>&1
        powercfg /set%%Avalueindex "!BUG_GUID!" SUB_DISK DISKIDLE 0 >nul 2>&1
        powercfg /set%%Avalueindex "!BUG_GUID!" SUB_PCIEXPRESS ASPM 0 >nul 2>&1
    )
    powercfg /setacvalueindex "!BUG_GUID!" SUB_PROCESSOR PERFINCPOL 2 >nul 2>&1
    powercfg /setacvalueindex "!BUG_GUID!" SUB_PROCESSOR PERFDECPOL 1 >nul 2>&1
    powercfg /setacvalueindex "!BUG_GUID!" SUB_PROCESSOR PERFINCTHRESHOLD 10 >nul 2>&1
    powercfg /setacvalueindex "!BUG_GUID!" SUB_PROCESSOR PERFDECTHRESHOLD 8 >nul 2>&1
    powercfg /setacvalueindex "!BUG_GUID!" SUB_PROCESSOR CPHEADROOM 0 >nul 2>&1
    powercfg /setacvalueindex "!BUG_GUID!" SUB_PROCESSOR LATENCYHINTPERF 100 >nul 2>&1
    powercfg /setacvalueindex "!BUG_GUID!" SUB_SLEEP HYBRIDSLEEP 0 >nul 2>&1
    powercfg /setacvalueindex "!BUG_GUID!" SUB_SLEEP RTCWAKE 0 >nul 2>&1
    powercfg /setacvalueindex "!BUG_GUID!" SUB_VIDEO ADAPTBRIGHT 0 >nul 2>&1
    powercfg /setacvalueindex "!BUG_GUID!" SUB_DISK DISKBURST 1 >nul 2>&1
    powercfg /setacvalueindex "!BUG_GUID!" SUB_NONE CONNECTIVITYINSTANDBY 0 >nul 2>&1
    powercfg /setactive "!BUG_GUID!" >nul 2>&1

    set "OTHER_PLANS=0"
    for /f "tokens=4" %%G in ('powercfg /list 2^>nul ^| findstr /i "Power Scheme GUID"') do (
        if /i "%%G" neq "!BUG_GUID!" set "OTHER_PLANS=1"
    )
    if "!OTHER_PLANS!"=="1" (
        echo [POWER] Outros planos detectados. Removendo...
        for /f "tokens=4" %%G in ('powercfg /list 2^>nul ^| findstr /i "Power Scheme GUID"') do (
            if /i "%%G" neq "!BUG_GUID!" powercfg /delete "%%G" >nul 2>&1
        )
        echo [POWER] Planos removidos.
    ) else (
        echo [POWER] Nenhum outro plano. Ignorando.
    )
    echo [POWER] Bug OPT ativo e configurado.
)

:: --- VISUAL EFFECTS -----------------------------------------------------------
set "VFX=-1" & set "ICONS=-1" & set "FONTS=-1" & set "DRAGFULL=-1" & set "MINANIM=-1"
for /f %%V in ('PowerShell -NoProfile -Command "try{(Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects').VisualFXSetting}catch{-1}"') do set "VFX=%%V"
for /f %%I in ('PowerShell -NoProfile -Command "try{(Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced').IconsOnly}catch{-1}"') do set "ICONS=%%I"
for /f %%F in ('PowerShell -NoProfile -Command "try{(Get-ItemProperty 'HKCU:\Control Panel\Desktop').FontSmoothing}catch{-1}"') do set "FONTS=%%F"
for /f %%X in ('PowerShell -NoProfile -Command "try{(Get-ItemProperty 'HKCU:\Control Panel\Desktop').DragFullWindows}catch{-1}"') do set "DRAGFULL=%%X"
for /f %%N in ('PowerShell -NoProfile -Command "try{(Get-ItemProperty 'HKCU:\Control Panel\Desktop\WindowMetrics').MinAnimate}catch{-1}"') do set "MINANIM=%%N"
if "!VFX!"=="3" if "!ICONS!"=="0" if "!FONTS!"=="2" if "!DRAGFULL!"=="0" if "!MINANIM!"=="0" (
    echo [VISUAL] Efeitos visuais ja configurados. Ignorando.
) else (
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
)

:: --- TEMP DO USUARIO ----------------------------------------------------------
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

:: --- TEMP DO WINDOWS ----------------------------------------------------------
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

:: --- PREFETCH -----------------------------------------------------------------
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

:: --- CACHE DO SISTEMA / NAVEGADORES / SHADER / MISC ----------------------------
set "CACHE_LIMPO=1"
set "CACHE_DIR_1=%LOCALAPPDATA%\Microsoft\Windows\INetCache"
set "CACHE_DIR_2=%LOCALAPPDATA%\Temp"
set "CACHE_DIR_3=%APPDATA%\Microsoft\Windows\Recent"
set "CACHE_DIR_4=%LOCALAPPDATA%\Microsoft\Windows\Explorer"
set "CACHE_DIR_5=%LOCALAPPDATA%\IconCache.db"
set "CACHE_DIR_6=%LOCALAPPDATA%\D3DSCache"
set "CACHE_DIR_7=%LOCALAPPDATA%\NVIDIA\DXCache"
set "CACHE_DIR_8=%LOCALAPPDATA%\NVIDIA\GLCache"
set "CACHE_DIR_9=%LOCALAPPDATA%\AMD\DxCache"
set "CACHE_DIR_10=%LOCALAPPDATA%\AMD\DxcCache"
set "CACHE_DIR_11=%LOCALAPPDATA%\AMD\GLCache"
set "CACHE_DIR_12=%LOCALAPPDATA%\Google\Chrome\User Data\Default\Cache"
set "CACHE_DIR_13=%LOCALAPPDATA%\Google\Chrome\User Data\Default\Code Cache"
set "CACHE_DIR_14=%LOCALAPPDATA%\Microsoft\Edge\User Data\Default\Cache"
set "CACHE_DIR_15=%LOCALAPPDATA%\Microsoft\Edge\User Data\Default\Code Cache"
set "CACHE_DIR_16=%LOCALAPPDATA%\Microsoft\Windows\WER"
set "CACHE_DIR_17=C:\ProgramData\Microsoft\Windows\WER"
set "CACHE_DIR_18=%LOCALAPPDATA%\CrashDumps"
set "CACHE_DIR_19=%LOCALAPPDATA%\Microsoft\Windows\Caches"
set "CACHE_DIR_20=C:\Windows\SoftwareDistribution\DeliveryOptimization"
set "CACHE_DIR_21=C:\Windows\Logs\CBS"
set "CACHE_DIR_22=C:\Windows\Logs\DPX"
set "CACHE_DIR_23=C:\Windows\Panther"
set "CACHE_DIR_24=C:\Windows\MEMORY.DMP"
set "CACHE_DIR_25=C:\Windows\Minidump"
set "CACHE_DIR_26=C:\Windows\ServiceProfiles\LocalService\AppData\Local\FontCache"
set "CACHE_DIR_27=%LOCALAPPDATA%\Microsoft\Windows\Thumbnail Cache"
set "CACHE_DIR_28=%APPDATA%\Discord\Cache"
set "CACHE_DIR_29=%APPDATA%\Discord\Code Cache"
set "CACHE_TOTAL=29"

for /l %%N in (1,1,!CACHE_TOTAL!) do (
    set "TARGET=!CACHE_DIR_%%N!"
    if exist "!TARGET!\" (
        for /f %%F in ('dir /b /a "!TARGET!" 2^>nul ^| find /c /v ""') do if %%F gtr 0 set "CACHE_LIMPO=0"
    ) else if exist "!TARGET!" (
        set "CACHE_LIMPO=0"
    )
)

:: cache real do Firefox (cache2), sem tocar no perfil (bookmarks/senhas ficam intactos)
if exist "%LOCALAPPDATA%\Mozilla\Firefox\Profiles\" (
    for /d %%P in ("%LOCALAPPDATA%\Mozilla\Firefox\Profiles\*") do (
        if exist "%%P\cache2\" (
            for /f %%F in ('dir /b /a "%%P\cache2" 2^>nul ^| find /c /v ""') do if %%F gtr 0 set "CACHE_LIMPO=0"
        )
    )
)

if "!CACHE_LIMPO!"=="0" (
    echo [CACHE] Limpando caches do sistema, navegadores e shaders...
    for /l %%N in (1,1,!CACHE_TOTAL!) do (
        set "TARGET=!CACHE_DIR_%%N!"
        if exist "!TARGET!\" (
            for /d %%X in ("!TARGET!\*") do rd /s /q "%%X" >nul 2>&1
            for %%X in ("!TARGET!\*") do del /f /q "%%X" >nul 2>&1
        ) else if exist "!TARGET!" (
            del /f /q "!TARGET!" >nul 2>&1
        )
    )
    if exist "%LOCALAPPDATA%\Mozilla\Firefox\Profiles\" (
        for /d %%P in ("%LOCALAPPDATA%\Mozilla\Firefox\Profiles\*") do (
            if exist "%%P\cache2\" (
                for /d %%X in ("%%P\cache2\*") do rd /s /q "%%X" >nul 2>&1
                for %%X in ("%%P\cache2\*") do del /f /q "%%X" >nul 2>&1
            )
        )
    )
    echo [CACHE] Concluido.
) else (
    echo [CACHE] Todos os caches ja limpos. Ignorando.
)

:: --- LIXEIRA ------------------------------------------------------------------
set "RECYCLE=0"
for /f %%R in ('PowerShell -NoProfile -Command "try{(New-Object -ComObject Shell.Application).NameSpace(10).Items().Count}catch{0}"') do set "RECYCLE=%%R"
if !RECYCLE! gtr 0 (
    echo [LIXEIRA] !RECYCLE! itens na Lixeira. Esvaziando...
    PowerShell -NoProfile -Command "Clear-RecycleBin -Force -ErrorAction SilentlyContinue" >nul 2>&1
    echo [LIXEIRA] Concluido.
) else (
    echo [LIXEIRA] Lixeira ja vazia. Ignorando.
)

:: --- WINDOWS UPDATE CACHE -----------------------------------------------------
set "WU_COUNT=0"
if exist "C:\Windows\SoftwareDistribution\Download\" (
    for /f %%F in ('dir /b /a "C:\Windows\SoftwareDistribution\Download" 2^>nul ^| find /c /v ""') do set "WU_COUNT=%%F"
)
if !WU_COUNT! gtr 0 (
    echo [WU] !WU_COUNT! itens em cache Windows Update. Limpando...
    net stop wuauserv /y >nul 2>&1
    net stop bits /y >nul 2>&1
    set "WU_STOPPED=0"
    for /l %%W in (1,1,10) do (
        if "!WU_STOPPED!"=="0" (
            sc query wuauserv | findstr /i "STOPPED" >nul 2>&1
            if not errorlevel 1 (
                set "WU_STOPPED=1"
            ) else (
                timeout /t 1 /nobreak >nul 2>&1
            )
        )
    )
    rd /s /q "C:\Windows\SoftwareDistribution\Download" >nul 2>&1
    mkdir "C:\Windows\SoftwareDistribution\Download" >nul 2>&1
    net start bits >nul 2>&1
    net start wuauserv >nul 2>&1
    echo [WU] Concluido.
) else (
    echo [WU] Cache Windows Update ja limpo. Ignorando.
)

:: --- LOGS DE EVENTOS E ARQUIVOS .LOG DO WINDOWS --------------------------------
set "EVTLOG_COUNT=0"
for /f %%L in ('PowerShell -NoProfile -Command "try{@(Get-WinEvent -ListLog * -ErrorAction SilentlyContinue ^| Where-Object {$_.RecordCount -gt 0}).Count}catch{0}"') do set "EVTLOG_COUNT=%%L"
if !EVTLOG_COUNT! gtr 0 (
    echo [EVTLOG] !EVTLOG_COUNT! logs de eventos com registros. Limpando...
    PowerShell -NoProfile -Command "try{Get-WinEvent -ListLog * -ErrorAction SilentlyContinue | Where-Object {$_.RecordCount -gt 0 -and $_.IsEnabled} | ForEach-Object { try { [System.Diagnostics.Eventing.Reader.EventLogSession]::GlobalSession.ClearLog($_.LogName) } catch {} }}catch{}" >nul 2>&1
    echo [EVTLOG] Concluido.
) else (
    echo [EVTLOG] Logs de eventos ja limpos. Ignorando.
)

set "SYSLOG_COUNT=0"
if exist "C:\Windows\Logs\" (
    for /f %%F in ('dir /b /s /a-d "C:\Windows\Logs\*.log" 2^>nul ^| find /c /v ""') do set "SYSLOG_COUNT=%%F"
)
if !SYSLOG_COUNT! gtr 0 (
    echo [LOGS] !SYSLOG_COUNT! arquivos .log em C:\Windows\Logs. Limpando...
    del /f /s /q "C:\Windows\Logs\*.log" >nul 2>&1
    echo [LOGS] Concluido.
) else (
    echo [LOGS] C:\Windows\Logs ja limpo. Ignorando.
)

:: --- TRIM SSD -----------------------------------------------------------------
set "SSD_COUNT=0"
for /f %%T in ('PowerShell -NoProfile -Command "try{@(Get-PhysicalDisk|Where-Object{$_.MediaType -eq 'SSD'}).Count}catch{0}"') do set "SSD_COUNT=%%T"
if !SSD_COUNT! gtr 0 (
    echo [TRIM] !SSD_COUNT! SSD(s) detectado(s). Executando TRIM...
    PowerShell -NoProfile -Command "try{Get-PhysicalDisk|Where-Object{$_.MediaType -eq 'SSD'}|ForEach-Object{$n=$_.DeviceId;Get-Partition -DiskNumber $n -ErrorAction SilentlyContinue|Where-Object{$_.DriveLetter}|ForEach-Object{Optimize-Volume -DriveLetter $_.DriveLetter -ReTrim -ErrorAction SilentlyContinue}}}catch{}" >nul 2>&1
    echo [TRIM] Concluido.
) else (
    echo [TRIM] Nenhum SSD detectado. Ignorando.
)

:: --- SERVICOS DESNECESSARIOS --------------------------------------------------
set "SVC_CHANGED=0"
for %%S in (DiagTrack WMPNetworkSvc XblAuthManager XblGameSave XboxNetApiSvc lfsvc MapsBroker RetailDemo WerSvc) do (
    set "SVC_TYPE=NotFound"
    set "SVC_STATUS=NotFound"
    for /f %%T in ('PowerShell -NoProfile -Command "try{(Get-Service -Name '%%S' -ErrorAction Stop).StartType}catch{'NotFound'}"') do set "SVC_TYPE=%%T"
    for /f %%U in ('PowerShell -NoProfile -Command "try{(Get-Service -Name '%%S' -ErrorAction Stop).Status}catch{'NotFound'}"') do set "SVC_STATUS=%%U"
    if /i "!SVC_TYPE!" neq "NotFound" if /i "!SVC_TYPE! !SVC_STATUS!" neq "Disabled Stopped" (
        PowerShell -NoProfile -Command "try{Stop-Service -Name '%%S' -Force -ErrorAction SilentlyContinue;Set-Service -Name '%%S' -StartupType Disabled -ErrorAction SilentlyContinue}catch{}" >nul 2>&1
        set "SVC_CHANGED=1"
    )
)
if "!SVC_CHANGED!"=="1" (
    echo [SERVICOS] Servicos desnecessarios desabilitados.
) else (
    echo [SERVICOS] Todos os servicos ja desabilitados. Ignorando.
)

:: --- TELEMETRIA ---------------------------------------------------------------
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

:: --- GAME MODE / GAME DVR -----------------------------------------------------
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

:: --- PAGINACAO / VIRTUAL MEMORY (AUTOMATICA POR SSD: BOOT=2420 / 2o=32768 / 3o=16384 / 4o=16384) ---
echo [PAGE] Detectando SSDs e configurando paginacao...

set "PAGE_PS=%TEMP%\BugOpt_PageFile.ps1"
if exist "!PAGE_PS!" del /f /q "!PAGE_PS!" >nul 2>&1

(
echo $ErrorActionPreference = 'Stop'
echo $results = @^(^)
echo try {
echo     ^$cs = Get-CimInstance -ClassName Win32_ComputerSystem
echo     if ^($cs.AutomaticManagedPagefile^) {
echo         Set-CimInstance -InputObject $cs -Property @{ AutomaticManagedPagefile = $false } ^| Out-Null
echo     }
echo } catch { }
echo $bootLetter = $null
echo try {
echo     $bootLetter = ^($env:SystemDrive^).TrimEnd^(':'^)
echo } catch { }
echo $ssdLetters = @^(^)
echo try {
echo     $disks = Get-PhysicalDisk ^| Where-Object { $_.MediaType -eq 'SSD' -and $_.BusType -in @^('SATA','NVMe','RAID'^) }
echo     foreach ^($disk in $disks^) {
echo         try {
echo             $parts = Get-Partition -DiskNumber $disk.DeviceId -ErrorAction SilentlyContinue ^| Where-Object { $_.DriveLetter }
echo             foreach ^($p in $parts^) {
echo                 $letter = [string]$p.DriveLetter
echo                 if ^($letter -and $ssdLetters -notcontains $letter^) { $ssdLetters += $letter }
echo             }
echo         } catch { }
echo     }
echo } catch { }
echo if ^(-not $bootLetter^) { $bootLetter = 'C' }
echo $ordered = @^(^)
echo if ^($ssdLetters -contains $bootLetter^) { $ordered += $bootLetter }
echo $rest = $ssdLetters ^| Where-Object { $_ -ne $bootLetter } ^| Sort-Object
echo foreach ^($r in $rest^) { $ordered += $r }
echo if ^($ordered.Count -gt 4^) { $ordered = $ordered[0..3] }
echo $sizeTable = @^(12288,20480,2048,2048^)
echo $index = 0
echo foreach ^($letter in $ordered^) {
echo     $size = $sizeTable[$index]
echo     $index++
echo     $drv = $letter + ':'
echo     try {
echo         $existing = Get-CimInstance -ClassName Win32_PageFileSetting -ErrorAction SilentlyContinue ^| Where-Object { $_.Name -eq "$drv\pagefile.sys" }
echo         if ^($existing^) {
echo             if ^($existing.InitialSize -ne $size -or $existing.MaximumSize -ne $size^) {
echo                 Set-CimInstance -InputObject $existing -Property @{ InitialSize = $size; MaximumSize = $size } ^| Out-Null
echo                 $results += "SET:$letter:$size"
echo             } else {
echo                 $results += "OK:$letter:$size"
echo             }
echo         } else {
echo             $newPF = New-CimInstance -ClassName Win32_PageFileSetting -Property @{ Name = "$drv\pagefile.sys"; InitialSize = $size; MaximumSize = $size } -ErrorAction Stop
echo             $results += "NEW:$letter:$size"
echo         }
echo     } catch {
echo         $results += "ERR:$letter:$($_.Exception.Message -replace '[:\r\n]',' '^)"
echo     }
echo }
echo try {
echo     $allSettings = Get-CimInstance -ClassName Win32_PageFileSetting -ErrorAction SilentlyContinue
echo     foreach ^($pf in $allSettings^) {
echo         $pfLetter = ^($pf.Name -split ':'^)[0]
echo         if ^($ordered -notcontains $pfLetter^) {
echo             $results += "OTHER:$pfLetter:untouched"
echo         }
echo     }
echo } catch { }
echo if ^($ordered.Count -eq 0^) { $results += "NONE:-:noSSD" }
echo foreach ^($line in $results^) { Write-Output $line }
) > "!PAGE_PS!"

set "PAGE_LOG=%TEMP%\BugOpt_PageResult.log"
if exist "!PAGE_LOG!" del /f /q "!PAGE_LOG!" >nul 2>&1

PowerShell -NoProfile -ExecutionPolicy Bypass -File "!PAGE_PS!" > "!PAGE_LOG!" 2>nul
del /f /q "!PAGE_PS!" >nul 2>&1

set "PAGE_HAD_LINES=0"
if exist "!PAGE_LOG!" (
    for /f "usebackq tokens=1,2,3 delims=:" %%A in ("!PAGE_LOG!") do (
        set "PAGE_HAD_LINES=1"
        set "STATUS=%%A"
        set "DRV=%%B"
        set "VAL=%%C"
        if "!STATUS!"=="OK"    echo [PAGE] Disco !DRV!: ja fixo em !VAL!MB. Ignorando.
        if "!STATUS!"=="SET"   echo [PAGE] Disco !DRV!: ajustado para !VAL!MB fixo.
        if "!STATUS!"=="NEW"   echo [PAGE] Disco !DRV!: pagefile criado com !VAL!MB fixo.
        if "!STATUS!"=="ERR"   echo [PAGE] Disco !DRV!: erro ao aplicar - !VAL!
        if "!STATUS!"=="OTHER" echo [PAGE] Disco !DRV!: pagefile existente mantido intacto.
        if "!STATUS!"=="NONE"  echo [PAGE] Nenhum SSD detectado. Nenhum pagefile aplicado.
    )
)
del /f /q "!PAGE_LOG!" >nul 2>&1

if "!PAGE_HAD_LINES!"=="0" (
    echo [PAGE] Falha ao executar verificacao de paginacao. Nenhuma alteracao aplicada.
) else (
    echo [PAGE] Verificacao concluida.
)

echo.
echo ============================================================
echo  Otimizacao finalizada com sucesso.
echo ============================================================
echo.
exit /b 0

@echo off
REM ============================================================
REM  JZ01-45-@ OpenStick Installer - Windows Setup
REM  Run as Administrator
REM ============================================================

setlocal enabledelayedexpansion

set WORKDIR=%~dp0
set EDLDIR=%WORKDIR%edl
set FILESDIR=%WORKDIR%files
set DLSDIR=%WORKDIR%dl
set VENV=%EDLDIR%\venv
set VPY=%VENV%\Scripts\python.exe

echo.
echo ============================================================
echo  JZ01-45-@ OpenStick Installer
echo ============================================================
echo  Work directory: %WORKDIR%
echo.

REM --- Administrator check ---
net session >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Run this script as Administrator.
    echo         Right-click install.bat -^> Run as administrator
    pause ^& exit /b 1
)

REM --- Path-with-spaces check ---
echo %WORKDIR% | find " " >nul
if not errorlevel 1 (
    echo [ERROR] Install path contains spaces: %WORKDIR%
    echo         Move the repo to e.g. C:\jz01-openstick and retry.
    pause ^& exit /b 1
)

REM --- winget availability ---
winget --version >nul 2>&1
if errorlevel 1 (
    echo [WARN] winget not available. fastboot/adb will need manual install.
    echo        Get App Installer from the Microsoft Store, or install
    echo        Android Platform Tools manually:
    echo        https://developer.android.com/tools/releases/platform-tools
    set HAVE_WINGET=0
) else (
    echo [OK] winget available
    set HAVE_WINGET=1
)

REM --- Python ---
python --version >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Python not found in PATH.
    echo         Install from https://www.python.org/downloads/
    echo         Check "Add Python to PATH" during install.
    pause ^& exit /b 1
)
for /f "tokens=2" %%i in ('python --version 2^>^&1') do set PYVER=%%i
echo [OK] Python %PYVER%

REM --- Git ---
git --version >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Git not found in PATH.
    echo         Install from https://git-scm.com/download/win
    pause ^& exit /b 1
)
echo [OK] Git available

REM --- WSL ---
wsl -l -q >nul 2>&1
if errorlevel 1 (
    echo [WARN] No WSL distro detected. Attempting install...
    wsl --install -d Ubuntu
    echo [INFO] Reboot and re-run install.bat when Ubuntu is ready.
    pause ^& exit /b 0
)
echo [OK] WSL available

REM --- fastboot (Android Platform Tools) ---
echo.
echo Checking for fastboot...
fastboot --version >nul 2>&1
if errorlevel 1 (
    if "!HAVE_WINGET!"=="1" (
        echo [WARN] fastboot not found. Installing Android Platform Tools via winget...
        winget install --id Google.PlatformTools --accept-source-agreements --accept-package-agreements -e
        if errorlevel 1 (
            echo [ERROR] winget install failed.
            echo         Install manually from:
            echo         https://developer.android.com/tools/releases/platform-tools
            echo         Then add the folder to PATH and re-run.
            pause ^& exit /b 1
        )
        echo [INFO] fastboot installed. PATH may not update until this window closes.
        echo        If the next check fails, close this window and re-run install.bat.
    ) else (
        echo [ERROR] fastboot not found and winget unavailable.
        echo         Install Android Platform Tools manually:
        echo         https://developer.android.com/tools/releases/platform-tools
        echo         Then add the folder to PATH and re-run.
        pause ^& exit /b 1
    )
)
fastboot --version >nul 2>&1
if errorlevel 1 (
    echo [ERROR] fastboot still not on PATH.
    echo         Close this window, open a NEW Administrator window,
    echo         and re-run install.bat.  (PATH changes need a new shell.)
    pause ^& exit /b 1
)
echo [OK] fastboot available

REM --- Directories ---
echo.
echo [1/7] Creating directories...
if not exist "%EDLDIR%"   mkdir "%EDLDIR%"
if not exist "%FILESDIR%" mkdir "%FILESDIR%"
if not exist "%DLSDIR%"   mkdir "%DLSDIR%"
echo [OK] Directories ready

REM --- Clone edl + venv ---
echo.
echo [2/7] Installing EDL tool...
if not exist "%EDLDIR%\edl.py" (
    git clone https://github.com/bkerler/edl.git "%EDLDIR%"
    if errorlevel 1 ( echo [ERROR] git clone failed. ^& pause ^& exit /b 1 )
)
if not exist "%VENV%\Scripts\python.exe" (
    python -m venv "%VENV%"
    if errorlevel 1 ( echo [ERROR] venv creation failed. ^& pause ^& exit /b 1 )
)
"%VPY%" -m pip install --upgrade pip >nul 2>&1
"%VPY%" -m pip install -r "%EDLDIR%\requirements.txt"
if errorlevel 1 ( echo [ERROR] pip install failed. ^& pause ^& exit /b 1 )
echo [OK] EDL tool installed

REM --- Download OpenStick kernel + rootfs ---
echo.
echo [3/7] Downloading OpenStick kernel and rootfs...
if not exist "%FILESDIR%\boot-ufi001c.img" (
    echo   - Kernel (~13 MB^)
    curl -L -o "%FILESDIR%\boot-ufi001c.img" ^
        "https://github.com/OpenStick/OpenStick/releases/download/v1/boot-ufi001c.img"
    if errorlevel 1 ( echo [ERROR] Kernel download failed. ^& pause ^& exit /b 1 )
)
if not exist "%DLSDIR%\debian.zip" (
    echo   - Debian rootfs (~360 MB, this may take a while^)
    curl -L -o "%DLSDIR%\debian.zip" ^
        "https://github.com/OpenStick/OpenStick/releases/download/v1/debian.zip"
    if errorlevel 1 ( echo [ERROR] Rootfs download failed. ^& pause ^& exit /b 1 )
)
echo [OK] OpenStick files downloaded

REM --- Download DragonBoard bootloader ---
echo.
echo [4/7] Downloading DragonBoard bootloader...
if not exist "%DLSDIR%\db-bootloader.zip" (
    echo   - DragonBoard 410c bootloader (~8 MB^)
    curl -L -o "%DLSDIR%\db-bootloader.zip" ^
        "https://storage.lavacloud.io/artifacts/dragonboard-410c/dragonboard-410c-bootloader-emmc-linux-176.zip"
    if errorlevel 1 ( echo [ERROR] Bootloader download failed. ^& pause ^& exit /b 1 )
)
echo [OK] Bootloader downloaded

REM --- Download lk2nd ---
echo.
echo [5/7] Downloading prebuilt lk2nd...
if not exist "%DLSDIR%\prebuilt.zip" (
    curl -L -o "%DLSDIR%\prebuilt.zip" ^
        "https://gist.github.com/kinsamanka/0b01cd02412bd13ee072072043d46fa2/raw/prebuilt.zip"
    if errorlevel 1 ( echo [ERROR] lk2nd download failed. ^& pause ^& exit /b 1 )
)
echo [OK] lk2nd downloaded

REM --- Extract ---
echo.
echo [6/7] Extracting files...
if not exist "%FILESDIR%\rootfs.img" (
    echo   - Debian rootfs
    powershell -NoProfile -Command "Expand-Archive -Path '%DLSDIR%\debian.zip' -DestinationPath '%DLSDIR%\db-extract' -Force"
    move /Y "%DLSDIR%\db-extract\debian\rootfs.img" "%FILESDIR%\rootfs.img" >nul
)
if not exist "%FILESDIR%\sbl1.mbn" (
    echo   - DragonBoard bootloader
    powershell -NoProfile -Command "Expand-Archive -Path '%DLSDIR%\db-bootloader.zip' -DestinationPath '%DLSDIR%\db-extract' -Force"
    for %%F in (sbl1.mbn rpm.mbn tz.mbn hyp.mbn sbc_1.0_8016.bin gpt_both0.bin) do (
        move /Y "%DLSDIR%\db-extract\dragonboard-410c-bootloader-emmc-linux-176\%%F" "%FILESDIR%\" >nul
    )
)
if not exist "%FILESDIR%\emmc_appsboot-test-signed.mbn" (
    echo   - lk2nd bootloader
    powershell -NoProfile -Command "Expand-Archive -Path '%DLSDIR%\prebuilt.zip' -DestinationPath '%FILESDIR%' -Force"
)
echo [OK] Files extracted

REM --- Patch GPT via WSL ---
echo.
echo [7/7] Patching GPT in WSL...
for /f "usebackq tokens=*" %%p in (`wsl wslpath -u "%WORKDIR%"`) do set WSLDIR=%%p
wsl bash -c "cd '!WSLDIR!' && chmod +x prep.sh && ./prep.sh"
if errorlevel 1 (
    echo [WARN] prep.sh failed. Run it manually in WSL:
    echo        wsl bash -c "cd '!WSLDIR!' ^&^& ./prep.sh"
)

echo.
echo ============================================================
echo  SETUP COMPLETE
echo ============================================================
echo.
echo Next steps:
echo   1. Put your JZ01-45-@ into EDL mode:
echo      - Unplug the dongle
echo      - Hold the reset/EDL button
echo      - Plug USB in while holding; release after 5 seconds
echo      - Verify "Qualcomm HS-USB QDLoader 9008" in Device Manager
echo   2. Run:  flash_edl.bat
echo.
echo Files are in: %FILESDIR%
echo.
pause@echo off
REM ============================================================
REM  JZ01-45-@ OpenStick Installer - Windows Setup
REM  Run as Administrator
REM ============================================================

setlocal enabledelayedexpansion

set WORKDIR=%~dp0
set EDLDIR=%WORKDIR%edl
set FILESDIR=%WORKDIR%files
set DLSDIR=%WORKDIR%dl
set VENV=%EDLDIR%\venv
set VPY=%VENV%\Scripts\python.exe

echo.
echo ============================================================
echo  JZ01-45-@ OpenStick Installer
echo ============================================================
echo  Work directory: %WORKDIR%
echo.

REM --- Administrator check ---
net session >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Run this script as Administrator.
    echo         Right-click install.bat -^> Run as administrator
    pause & exit /b 1
)

REM --- Path-with-spaces check ---
echo %WORKDIR% | find " " >nul
if not errorlevel 1 (
    echo [ERROR] Install path contains spaces: %WORKDIR%
    echo         Move the repo to e.g. C:\jz01-openstick and retry.
    pause & exit /b 1
)

REM --- Python ---
python --version >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Python not found in PATH.
    echo         Install from https://www.python.org/downloads/
    echo         Check "Add Python to PATH" during install.
    pause & exit /b 1
)
for /f "tokens=2" %%i in ('python --version 2^>^&1') do set PYVER=%%i
echo [OK] Python %PYVER%

REM --- Git ---
git --version >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Git not found in PATH.
    echo         Install from https://git-scm.com/download/win
    pause & exit /b 1
)
echo [OK] Git available

REM --- WSL ---
wsl -l -q >nul 2>&1
if errorlevel 1 (
    echo [WARN] No WSL distro detected. Attempting install...
    wsl --install -d Ubuntu
    echo [INFO] Reboot and re-run install.bat when Ubuntu is ready.
    pause & exit /b 0
)
echo [OK] WSL available

REM --- Directories ---
echo.
echo [1/7] Creating directories...
if not exist "%EDLDIR%"   mkdir "%EDLDIR%"
if not exist "%FILESDIR%" mkdir "%FILESDIR%"
if not exist "%DLSDIR%"   mkdir "%DLSDIR%"
echo [OK] Directories ready

REM --- Clone edl + venv ---
echo.
echo [2/7] Installing EDL tool...
if not exist "%EDLDIR%\edl.py" (
    git clone https://github.com/bkerler/edl.git "%EDLDIR%"
    if errorlevel 1 ( echo [ERROR] git clone failed. & pause & exit /b 1 )
)
if not exist "%VENV%\Scripts\python.exe" (
    python -m venv "%VENV%"
    if errorlevel 1 ( echo [ERROR] venv creation failed. & pause & exit /b 1 )
)
"%VPY%" -m pip install --upgrade pip >nul 2>&1
"%VPY%" -m pip install -r "%EDLDIR%\requirements.txt"
if errorlevel 1 ( echo [ERROR] pip install failed. & pause & exit /b 1 )
echo [OK] EDL tool installed

REM --- Download OpenStick kernel + rootfs ---
echo.
echo [3/7] Downloading OpenStick kernel and rootfs...
if not exist "%FILESDIR%\boot-ufi001c.img" (
    echo   - Kernel (~13 MB^)
    curl -L -o "%FILESDIR%\boot-ufi001c.img" ^
        "https://github.com/OpenStick/OpenStick/releases/download/v1/boot-ufi001c.img"
    if errorlevel 1 ( echo [ERROR] Kernel download failed. & pause & exit /b 1 )
)
if not exist "%DLSDIR%\debian.zip" (
    echo   - Debian rootfs (~360 MB, this may take a while^)
    curl -L -o "%DLSDIR%\debian.zip" ^
        "https://github.com/OpenStick/OpenStick/releases/download/v1/debian.zip"
    if errorlevel 1 ( echo [ERROR] Rootfs download failed. & pause & exit /b 1 )
)
echo [OK] OpenStick files downloaded

REM --- Download DragonBoard bootloader ---
echo.
echo [4/7] Downloading DragonBoard bootloader...
if not exist "%DLSDIR%\db-bootloader.zip" (
    echo   - DragonBoard 410c bootloader (~8 MB^)
    curl -L -o "%DLSDIR%\db-bootloader.zip" ^
        "https://storage.lavacloud.io/artifacts/dragonboard-410c/dragonboard-410c-bootloader-emmc-linux-176.zip"
    if errorlevel 1 ( echo [ERROR] Bootloader download failed. & pause & exit /b 1 )
)
echo [OK] Bootloader downloaded

REM --- Download lk2nd ---
echo.
echo [5/7] Downloading prebuilt lk2nd...
if not exist "%DLSDIR%\prebuilt.zip" (
    curl -L -o "%DLSDIR%\prebuilt.zip" ^
        "https://gist.github.com/kinsamanka/0b01cd02412bd13ee072072043d46fa2/raw/prebuilt.zip"
    if errorlevel 1 ( echo [ERROR] lk2nd download failed. & pause & exit /b 1 )
)
echo [OK] lk2nd downloaded

REM --- Extract ---
echo.
echo [6/7] Extracting files...
if not exist "%FILESDIR%\rootfs.img" (
    echo   - Debian rootfs
    powershell -NoProfile -Command "Expand-Archive -Path '%DLSDIR%\debian.zip' -DestinationPath '%DLSDIR%\db-extract' -Force"
    move /Y "%DLSDIR%\db-extract\debian\rootfs.img" "%FILESDIR%\rootfs.img" >nul
)
if not exist "%FILESDIR%\sbl1.mbn" (
    echo   - DragonBoard bootloader
    powershell -NoProfile -Command "Expand-Archive -Path '%DLSDIR%\db-bootloader.zip' -DestinationPath '%DLSDIR%\db-extract' -Force"
    for %%F in (sbl1.mbn rpm.mbn tz.mbn hyp.mbn sbc_1.0_8016.bin gpt_both0.bin) do (
        move /Y "%DLSDIR%\db-extract\dragonboard-410c-bootloader-emmc-linux-176\%%F" "%FILESDIR%\" >nul
    )
)
if not exist "%FILESDIR%\emmc_appsboot-test-signed.mbn" (
    echo   - lk2nd bootloader
    powershell -NoProfile -Command "Expand-Archive -Path '%DLSDIR%\prebuilt.zip' -DestinationPath '%FILESDIR%' -Force"
)
echo [OK] Files extracted

REM --- Patch GPT via WSL ---
echo.
echo [7/7] Patching GPT in WSL...
for /f "usebackq tokens=*" %%p in (`wsl wslpath -u "%WORKDIR%"`) do set WSLDIR=%%p
wsl bash -c "cd %WSLDIR% && chmod +x prep.sh && ./prep.sh"
if errorlevel 1 (
    echo [WARN] prep.sh failed. Run manually in WSL:
    echo        cd %WSLDIR% ^&^& ./prep.sh
)

echo.
echo ============================================================
echo  SETUP COMPLETE
echo ============================================================
echo.
echo Next steps:
echo   1. Put your JZ01-45-@ into EDL mode:
echo      - Unplug the dongle
echo      - Hold the reset/EDL button
echo      - Plug USB in while holding; release after 5 s
echo      - Verify "Qualcomm HS-USB QDLoader 9008" in Device Manager
echo   2. Run:  flash_edl.bat
echo.
echo Files are in: %FILESDIR%
echo.
pause

@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"

set "WORKDIR=%CD%"
set "EDLDIR=%WORKDIR%\edl"
set "FILESDIR=%WORKDIR%\files"
set "DLSDIR=%WORKDIR%\dl"
set "VENV=%EDLDIR%\venv"
set "VPY=%VENV%\Scripts\python.exe"

echo ============================================================
echo  JZ01-45-@ OpenStick Installer
echo ============================================================
echo  Work directory: %WORKDIR%
echo.

net session >nul 2>&1
if errorlevel 1 ( echo [ERROR] Run as Administrator. & pause & exit /b 1 )

set "WORKDIR_NOSPACE=%WORKDIR: =%"
if not "%WORKDIR%"=="%WORKDIR_NOSPACE%" (
  echo [ERROR] Path contains spaces: %WORKDIR%
  pause & exit /b 1
)

where python >nul 2>&1 || ( echo [ERROR] Python not in PATH. & pause & exit /b 1 )
where git    >nul 2>&1 || ( echo [ERROR] Git not in PATH.    & pause & exit /b 1 )
wsl -l -q    >nul 2>&1 || ( echo [ERROR] WSL not installed.  & pause & exit /b 1 )

echo [OK] Prerequisites present
echo.

echo [1/7] Creating directories...
if not exist "%EDLDIR%"   mkdir "%EDLDIR%"
if not exist "%FILESDIR%" mkdir "%FILESDIR%"
if not exist "%DLSDIR%"   mkdir "%DLSDIR%"
echo [OK] Directories ready

echo.
echo [2/7] Installing EDL tool...
if not exist "%EDLDIR%\edl.py" git clone https://github.com/bkerler/edl.git "%EDLDIR%"
if not exist "%VENV%\Scripts\python.exe" python -m venv "%VENV%"
"%VPY%" -m pip install --upgrade pip >nul 2>&1
"%VPY%" -m pip install -r "%EDLDIR%\requirements.txt"
echo [OK] EDL tool installed

echo.
echo [3/7] Downloading OpenStick kernel + rootfs...
if not exist "%FILESDIR%\boot-ufi001c.img" (
  curl -L -o "%FILESDIR%\boot-ufi001c.img" ^
    "https://github.com/OpenStick/OpenStick/releases/download/v1/boot-ufi001c.img"
)
if not exist "%FILESDIR%\rootfs.img" (
  if not exist "%DLSDIR%\debian.zip" (
    curl -L -o "%DLSDIR%\debian.zip" ^
      "https://github.com/OpenStick/OpenStick/releases/download/v1/debian.zip"
  )
)
echo [OK] OpenStick files ready

echo.
echo [4/7] Downloading DragonBoard bootloader...
if not exist "%DLSDIR%\db-bootloader.zip" (
  curl -L -o "%DLSDIR%\db-bootloader.zip" ^
    "https://storage.lavacloud.io/artifacts/dragonboard-410c/dragonboard-410c-bootloader-emmc-linux-176.zip"
)
echo [OK] Bootloader downloaded

echo.
echo [5/7] Downloading prebuilt lk2nd...
if not exist "%DLSDIR%\prebuilt.zip" (
  curl -L -o "%DLSDIR%\prebuilt.zip" ^
    "https://gist.github.com/kinsamanka/0b01cd02412bd13ee072072043d46fa2/raw/prebuilt.zip"
)
echo [OK] lk2nd downloaded

echo.
echo [6/7] Extracting files...
if not exist "%FILESDIR%\rootfs.img" (
  powershell -NoProfile -Command "Expand-Archive -Path '%DLSDIR%\debian.zip' -DestinationPath '%DLSDIR%\db-extract' -Force"
  move /Y "%DLSDIR%\db-extract\debian\rootfs.img" "%FILESDIR%\rootfs.img" >nul
)
if not exist "%FILESDIR%\sbl1.mbn" (
  powershell -NoProfile -Command "Expand-Archive -Path '%DLSDIR%\db-bootloader.zip' -DestinationPath '%DLSDIR%\db-extract' -Force"
  for %%F in (sbl1.mbn rpm.mbn tz.mbn hyp.mbn sbc_1.0_8016.bin gpt_both0.bin) do (
    move /Y "%DLSDIR%\db-extract\dragonboard-410c-bootloader-emmc-linux-176\%%F" "%FILESDIR%\" >nul
  )
)
if not exist "%FILESDIR%\emmc_appsboot-test-signed.mbn" (
  powershell -NoProfile -Command "Expand-Archive -Path '%DLSDIR%\prebuilt.zip' -DestinationPath '%FILESDIR%' -Force"
)
echo [OK] Files extracted

echo.
echo [7/7] Downloading Firehose loader...
if not exist "%EDLDIR%\Loaders\custom" mkdir "%EDLDIR%\Loaders\custom"
if not exist "%EDLDIR%\Loaders\custom\prog_emmc_firehose_8916.mbn" (
  curl -L -o "%EDLDIR%\Loaders\custom\prog_emmc_firehose_8916.mbn" ^
    "https://raw.githubusercontent.com/OneLabsTools/Programmers/master/prog_emmc_firehose_8916.mbn"
)
echo [OK] Loader ready

echo.
echo Patching GPT in WSL...
for /f "usebackq tokens=*" %%p in (`wsl wslpath -u "%WORKDIR%"`) do set "WSLDIR=%%p"
wsl bash -c "cd '!WSLDIR!' && chmod +x prep.sh && ./prep.sh"

echo.
echo Running fix_gpt.py to resize rootfs...
if exist fix_gpt.py python fix_gpt.py

echo.
echo ============================================================
echo  SETUP COMPLETE
echo ============================================================
echo.
echo Next:
echo   1. Enter EDL mode (unplug, hold reset, plug USB, release after 5 s)
echo   2. Run:  flash_edl.bat
echo.
pause

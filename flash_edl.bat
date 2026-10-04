@echo off
REM ============================================================
REM  flash_edl.bat - Flash OpenStick to JZ01-45-@ via EDL + fastboot
REM  Run as Administrator with dongle in EDL mode.
REM ============================================================

setlocal enabledelayedexpansion

set WORKDIR=%~dp0
set EDLDIR=%WORKDIR%edl
set FILESDIR=%WORKDIR%files
set OUTFILE=%WORKDIR%output
set VPY=%EDLDIR%\venv\Scripts\python.exe
set EDLPY=%EDLDIR%\edl.py

if not exist "%VPY%" (
    echo [ERROR] Python venv not found at %VPY%
    echo         Run install.bat first.
    pause & exit /b 1
)

echo.
echo ============================================================
echo  JZ01-45-@ OpenStick Flasher
echo ============================================================
echo.

REM --- 1. Verify EDL ---
echo [1/7] Verifying EDL connection...
"%VPY%" "%EDLPY%" printgpt --memory=eMMC
if errorlevel 1 (
    echo.
    echo [ERROR] Device not detected in EDL mode.
    echo   1. Unplug the dongle
    echo   2. Hold the reset/EDL button
    echo   3. Plug USB in while holding; release after 5 s
    echo   4. Verify "Qualcomm HS-USB QDLoader 9008" in Device Manager
    pause & exit /b 1
)
echo [OK] Device in EDL mode

REM --- 2. Backup firmware ---
echo.
echo [2/7] Backing up current firmware...
if not exist "%WORKDIR%orig_fw" mkdir "%WORKDIR%orig_fw"
for /f %%i in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd"') do set DATESTR=%%i
set BACKUP_FILE=%WORKDIR%orig_fw\orig_fw_%DATESTR%.bin
echo   Saving to: !BACKUP_FILE!
echo   (This takes 15-20 minutes, ~3.9 GB^)

"%VPY%" "%EDLPY%" rf "!BACKUP_FILE!"
if errorlevel 1 (
    echo [ERROR] Firmware backup failed. Aborting.
    pause & exit /b 1
)
echo [OK] Backup saved

REM --- 3. Backup OEM partitions ---
echo.
echo [3/7] Backing up OEM calibration partitions...
for %%P in (modemst1 modemst2 persist fsg fsc sec) do (
    echo   - %%P
    "%VPY%" "%EDLPY%" r %%P "%WORKDIR%orig_fw\%%P.bin" --memory=eMMC
    if errorlevel 1 (
        echo [WARN] Failed to back up %%P (continuing^)
    )
)
echo [OK] OEM partitions backed up

REM --- 4. Flash patched GPT ---
echo.
echo [4/7] Flashing patched GPT...
if not exist "%OUTFILE%\gpt_main_fixed.bin" (
    echo [ERROR] Patched GPT not found in %OUTFILE%
    echo         Run install.bat first.
    pause & exit /b 1
)
"%VPY%" "%EDLPY%" ws 0        "%OUTFILE%\gpt_main_fixed.bin"   --memory=eMMC
if errorlevel 1 goto :fail
"%VPY%" "%EDLPY%" ws 7569375  "%OUTFILE%\gpt_backup_fixed.bin" --memory=eMMC
if errorlevel 1 goto :fail
echo [OK] GPT flashed

REM --- 5. Flash bootloader chain ---
echo.
echo [5/7] Flashing bootloader chain...
for %%P in (sbl1 rpm tz hyp) do (
    if exist "%FILESDIR%\%%P.mbn" (
        echo   - %%P
        "%VPY%" "%EDLPY%" w %%P "%FILESDIR%\%%P.mbn" --memory=eMMC
        if errorlevel 1 goto :fail
    ) else (
        echo [ERROR] Missing %FILESDIR%\%%P.mbn
        goto :fail
    )
)
if exist "%FILESDIR%\sbc_1.0_8016.bin" (
    echo   - cdt
    "%VPY%" "%EDLPY%" w cdt "%FILESDIR%\sbc_1.0_8016.bin" --memory=eMMC
)
if not exist "%FILESDIR%\emmc_appsboot-test-signed.mbn" (
    echo [ERROR] Missing lk2nd image emmc_appsboot-test-signed.mbn
    goto :fail
)
echo   - aboot (lk2nd)
"%VPY%" "%EDLPY%" w aboot    "%FILESDIR%\emmc_appsboot-test-signed.mbn" --memory=eMMC
if errorlevel 1 goto :fail
echo   - abootbak (lk2nd)
"%VPY%" "%EDLPY%" w abootbak "%FILESDIR%\emmc_appsboot-test-signed.mbn" --memory=eMMC
if errorlevel 1 goto :fail
echo [OK] Bootloader flashed

REM --- 6. Restore OEM calibration (via EDL, before leaving EDL) ---
echo.
echo [6/7] Restoring OEM calibration partitions...
for %%P in (modemst1 modemst2 persist fsg fsc sec) do (
    if exist "%WORKDIR%orig_fw\%%P.bin" (
        echo   - %%P
        "%VPY%" "%EDLPY%" w %%P "%WORKDIR%orig_fw\%%P.bin" --memory=eMMC
        if errorlevel 1 echo [WARN] Failed to restore %%P (continuing^)
    ) else (
        echo [WARN] Missing backup for %%P (skipping^)
    )
)
echo [OK] OEM partitions restored

REM --- 7. Reset -> lk2nd fastboot -> flash boot + rootfs ---
echo.
echo [7/7] Resetting into lk2nd fastboot...
"%VPY%" "%EDLPY%" reset
echo.
echo   Waiting 20 seconds for lk2nd to expose fastboot...
timeout /t 20 /nobreak >nul

fastboot devices | findstr /r "." >nul
if errorlevel 1 (
    echo [ERROR] No fastboot device.
    echo         Replug USB and re-run flash_edl.bat; it will resume.
    pause & exit /b 1
)
echo [OK] Device in fastboot

echo.
echo Flashing OpenStick (boot + rootfs)...
if not exist "%FILESDIR%\boot-ufi001c.img" (
    echo [ERROR] Missing %FILESDIR%\boot-ufi001c.img
    goto :fail
)
if not exist "%FILESDIR%\rootfs.img" (
    echo [ERROR] Missing %FILESDIR%\rootfs.img
    goto :fail
)

fastboot flash boot "%FILESDIR%\boot-ufi001c.img"
if errorlevel 1 goto :fail

echo   - Writing rootfs (this takes a few minutes^)...
fastboot flash rootfs "%FILESDIR%\rootfs.img"
if errorlevel 1 goto :fail

echo.
echo Rebooting into Debian...
fastboot reboot

echo.
echo ============================================================
echo  FLASH COMPLETE
echo ============================================================
echo.
echo First boot takes 2-3 minutes. Then:
echo   1. Find the dongle's IP on your router.
echo   2. ssh root@^<dongle-ip^>       (password: openstick^)
echo   3. bash post_config.sh
echo.
pause
exit /b 0

:fail
echo.
echo ============================================================
echo  FLASH FAILED
echo ============================================================
echo.
echo Your original firmware backup is at:
echo   %WORKDIR%orig_fw\
echo.
echo To restore Android:
echo   edl\venv\Scripts\python edl\edl.py wf %WORKDIR%orig_fw\orig_fw_*.bin --memory=eMMC
echo   edl\venv\Scripts\python edl\edl.py reset
echo.
pause
exit /b 1

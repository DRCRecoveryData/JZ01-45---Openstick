@echo off
setlocal
cd /d "%~dp0"

set "PY=edl\venv\Scripts\python.exe"
set "EDL=edl\edl.py"
set "LOADER=edl\Loaders\custom\prog_emmc_firehose_8916.mbn"
set "FILES=files"
set "OUT=output"

if not exist "%PY%"     ( echo [ERROR] venv missing & pause & exit /b 1 )
if not exist "%LOADER%" ( echo [ERROR] loader missing: %LOADER% & pause & exit /b 1 )
if not exist "%OUT%\gpt_main_rootfs.bin" (
  echo [ERROR] output\gpt_main_rootfs.bin missing
  echo         Run install.bat or fix_gpt.py first.
  pause & exit /b 1
)

echo ============================================================
echo  OpenStick flash for JZ01-45-@
echo ============================================================
echo.

echo [1/7] Verifying EDL connection...
"%PY%" "%EDL%" --loader "%LOADER%" printgpt --memory=eMMC
if errorlevel 1 ( echo [ERROR] device not in EDL & pause & exit /b 1 )

echo.
echo [2/7] Backing up firmware (~3.9 GB, 15-20 min)...
if not exist orig_fw mkdir orig_fw
for /f %%i in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss"') do set TS=%%i
"%PY%" "%EDL%" --loader "%LOADER%" rf "orig_fw\pre_openstick_%TS%.bin" --memory=eMMC
if errorlevel 1 ( echo [ERROR] backup failed & pause & exit /b 1 )

echo.
echo [3/7] Writing patched GPT...
"%PY%" "%EDL%" --loader "%LOADER%" ws 0 "%OUT%\gpt_main_rootfs.bin" --memory=eMMC
if errorlevel 1 ( echo [ERROR] main GPT failed & pause & exit /b 1 )
"%PY%" "%EDL%" --loader "%LOADER%" ws 7569375 "%OUT%\gpt_backup_rootfs.bin" --memory=eMMC
if errorlevel 1 ( echo [ERROR] backup GPT failed & pause & exit /b 1 )

echo.
echo [4/7] Writing bootloader chain...
for %%P in (sbl1 rpm tz hyp) do (
  if exist "%FILES%\%%P.mbn" (
    echo   - %%P
    "%PY%" "%EDL%" --loader "%LOADER%" w %%P "%FILES%\%%P.mbn" --memory=eMMC
    if errorlevel 1 ( echo [ERROR] %%P failed & pause & exit /b 1 )
  )
)
if exist "%FILES%\sbc_1.0_8016.bin" (
  echo   - cdt
  "%PY%" "%EDL%" --loader "%LOADER%" w cdt "%FILES%\sbc_1.0_8016.bin" --memory=eMMC
)

echo.
echo [5/7] Writing lk2nd to aboot...
"%PY%" "%EDL%" --loader "%LOADER%" w aboot "%FILES%\emmc_appsboot-test-signed.mbn" --memory=eMMC
if errorlevel 1 ( echo [ERROR] aboot write failed & pause & exit /b 1 )

echo.
echo [6/7] Writing kernel (boot)...
"%PY%" "%EDL%" --loader "%LOADER%" w boot "%FILES%\boot-ufi001c.img" --memory=eMMC
if errorlevel 1 ( echo [ERROR] boot write failed & pause & exit /b 1 )

echo.
echo [7/7] Writing Debian rootfs (~3 min)...
"%PY%" "%EDL%" --loader "%LOADER%" w rootfs "%FILES%\rootfs.img" --memory=eMMC
if errorlevel 1 ( echo [ERROR] rootfs write failed & pause & exit /b 1 )

echo.
echo ============================================================
echo  FLASH COMPLETE
echo ============================================================
echo.
echo   Unplug USB, wait 60 s, plug back in (no reset button).
echo   Debian boots in 2-3 min.
echo   Default password: openstick
echo.
echo   Note: `edl reset` doesn't work on this hardware --
echo         physical power cycle is required.
echo.
pause

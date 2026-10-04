# make_flash.py - writes flash_edl.bat with proper CRLF/ASCII encoding
content = r'''@echo off
setlocal
cd /d "%~dp0"

set "PY=edl\venv\Scripts\python.exe"
set "EDL=edl\edl.py"
set "LOADER=edl\Loaders\custom\prog_emmc_firehose_8916.mbn"
set "FILES=files"
set "OUT=output"

if not exist "%PY%"     ( echo [ERROR] venv missing & pause & exit /b 1 )
if not exist "%LOADER%" ( echo [ERROR] loader missing: %LOADER% & pause & exit /b 1 )
if not exist "%OUT%\gpt_main_rootfs.bin" ( echo [ERROR] run fix_gpt.py first & pause & exit /b 1 )

echo [1/7] Verifying EDL...
"%PY%" "%EDL%" --loader "%LOADER%" printgpt --memory=eMMC
if errorlevel 1 ( echo [ERROR] not in EDL & pause & exit /b 1 )

echo [2/7] Backing up firmware...
if not exist orig_fw mkdir orig_fw
for /f %%i in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss"') do set TS=%%i
"%PY%" "%EDL%" --loader "%LOADER%" rf "orig_fw\pre_openstick_%TS%.bin" --memory=eMMC
if errorlevel 1 ( echo [ERROR] backup failed & pause & exit /b 1 )

echo [3/7] Writing GPT...
"%PY%" "%EDL%" --loader "%LOADER%" ws 0 "%OUT%\gpt_main_rootfs.bin" --memory=eMMC
"%PY%" "%EDL%" --loader "%LOADER%" ws 7569375 "%OUT%\gpt_backup_rootfs.bin" --memory=eMMC

echo [4/7] Writing bootloader...
for %%P in (sbl1 rpm tz hyp) do (
  if exist "%FILES%\%%P.mbn" "%PY%" "%EDL%" --loader "%LOADER%" w %%P "%FILES%\%%P.mbn" --memory=eMMC
)
if exist "%FILES%\sbc_1.0_8016.bin" "%PY%" "%EDL%" --loader "%LOADER%" w cdt "%FILES%\sbc_1.0_8016.bin" --memory=eMMC

echo [5/7] Writing lk2nd to aboot...
"%PY%" "%EDL%" --loader "%LOADER%" w aboot "%FILES%\emmc_appsboot-test-signed.mbn" --memory=eMMC

echo [6/7] Writing kernel...
"%PY%" "%EDL%" --loader "%LOADER%" w boot "%FILES%\boot-ufi001c.img" --memory=eMMC

echo [7/7] Writing rootfs...
"%PY%" "%EDL%" --loader "%LOADER%" w rootfs "%FILES%\rootfs.img" --memory=eMMC

echo DONE. Unplug, wait 60 s, replug (no button).
pause
'''

with open(r"C:\jz01-openstick\flash_edl.bat", "w", encoding="ascii", newline="\r\n") as f:
    f.write(content)
print("Wrote flash_edl.bat")

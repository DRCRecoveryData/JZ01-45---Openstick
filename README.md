# JZ01-45-@ OpenStick Installer

One-click installer for running Debian 11 (OpenStick) on the **JZ01-45-@** (MSM8916) 4G dongle.

**Tested on:** JZ01-45-@ hardware, firmware version from sticker (IMEI 864894077216761)
**Result:** Working Debian 11 aarch64, WiFi client, SSH, LEDs, reset button

---

## ⚠️ Read This First

- **This will erase Android** from your dongle.
- **Backup required:** Save `orig_fw_trunc.bin` (or any full eMMC dump) to external storage.
- **Only for JZ01-45-@** (or compatible MSM8916 UFI dongles).
- **Not for V33** — use kinsamanka's gist instead.
- Cellular (SIM) will **not work** unless you have proper IMEI/calibration.

---

## 📋 Requirements

| Item | Notes |
|---|---|
| Windows 10/11 | |
| WSL2 with Ubuntu | `wsl --install` in PowerShell |
| Python 3.9+ | On Windows |
| Git for Windows | https://git-scm.com/download/win |
| Qualcomm USB Drivers | Or `libusb-win32` via Zadig |
| ~10 GB free space | For downloads and extractions |
| USB cable | Data-capable, not charge-only |

---

## 🚀 Quick Start (3 Steps)

### Step 1: Prepare (Windows)

Double-click **`install.bat`** — it will:
1. Install the `edl` Python tool
2. Download OpenStick kernel + Debian rootfs
3. Download DragonBoard bootloader files
4. Prepare a patched GPT for JZ01-45-@
5. Build `patched.dtb`

### Step 2: Flash (Windows)

Double-click **`flash_edl.bat`** — it will:
1. Put your dongle in EDL mode (you do this manually)
2. Back up your current firmware
3. Flash OpenStick + bootloader chain
4. Restore OEM calibration partitions
5. Reboot

### Step 3: Configure (SSH into the dongle)

Once it boots, SSH in:

    ssh root@<dongle-ip>

Then run:

    bash post_config.sh

This sets up:
- WiFi auto-connect (you supply SSID + password)
- SSH service on port 22
- LED triggers (WiFi activity, USB, heartbeat)
- Reset button as graceful shutdown

---

## 📁 What Gets Installed

| Partition | Content |
|---|---|
| `aboot`, `abootbak` | lk2nd bootloader |
| `sbl1`, `rpm`, `tz`, `hyp` | DragonBoard 410c bootloader |
| `cdt` | DragonBoard CDT |
| `boot` | OpenStick kernel (with working DTB) |
| `rootfs` | Debian 11 rootfs |
| `modemst1`, `modemst2` | **Preserved** — your original IMEI |
| `persist` | **Preserved** — your original WiFi MAC |
| `fsg`, `fsc`, `sec` | **Preserved** — calibration data |

---

## 🔧 Files Explained

| File | Purpose |
|---|---|
| `install.bat` | Master installer — downloads everything |
| `prep.sh` | WSL-side GPT patch script |
| `flash_edl.bat` | EDL flash sequence |
| `post_config.sh` | On-device configuration |
| `docs/RECOVERY.md` | How to restore Android |
| `docs/TROUBLESHOOTING.md` | Common issues |

---

## 📞 Post-Install Defaults

| Setting | Value |
|---|---|
| Root password | `openstick` (change it!) |
| WiFi | Client mode — connects to your home WiFi |
| SSH | Enabled on port 22 |
| Hostname | `openstick` |
| LEDs | WiFi TX / USB gadget / heartbeat |

---

## 🔄 Restoring Android

If you want to go back to Android:

1. Enter EDL mode on the dongle
2. Run:
   ```
   edl wf C:\path\to\orig_fw_trunc.bin --memory=eMMC
   edl reset
   ```
3. Wait 5-10 minutes for boot

Full recovery instructions: [`docs/RECOVERY.md`](docs/RECOVERY.md)

---

## 📜 Credits

- **kinsamanka** — original OpenStick installation gist
- **bkerler** — `edl` tool for Qualcomm EDL
- **OpenStick project** — kernel and rootfs
- **96boards.org** — DragonBoard bootloader

This project is a **streamlined repackaging** with:
- Recovery steps for corrupted/bricked boards
- GPT patching for JZ01-45-@ disk size
- Automated downloads (including dead-link workarounds)
- Post-install WiFi/LED/button configuration

---

## ⚖️ License

MIT — do whatever you want, no warranty.

---

## 💬 Support

This is a hobby project. If something breaks, you're on your own — but [`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md) covers the common issues.
```

---

## 📄 2. `install.bat` (Windows Master Installer)

```batch
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

echo.
echo ============================================================
echo  JZ01-45-@ OpenStick Installer
echo ============================================================
echo.
echo  Work directory: %WORKDIR%
echo.

REM --- Check for Administrator ---
net session >nul 2>&1
if errorlevel 1 (
    echo [ERROR] This script must be run as Administrator.
    echo         Right-click install.bat -^> Run as administrator
    pause
    exit /b 1
)

REM --- Check for Python ---
python --version >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Python is not installed or not in PATH.
    echo         Download from https://www.python.org/downloads/
    echo         IMPORTANT: Check "Add Python to PATH" during install.
    pause
    exit /b 1
)
for /f "tokens=2" %%i in ('python --version 2^>^&1') do set PYVER=%%i
echo [OK] Python %PYVER%

REM --- Check for Git ---
git --version >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Git is not installed or not in PATH.
    echo         Download from https://git-scm.com/download/win
    pause
    exit /b 1
)
echo [OK] Git is available

REM --- Check for WSL ---
wsl --status >nul 2>&1
if errorlevel 1 (
    echo [WARN] WSL not detected. Attempting to install...
    echo.
    wsl --install -d Ubuntu
    echo.
    echo [INFO] WSL installation started. Please reboot and re-run this script.
    pause
    exit /b 0
)
echo [OK] WSL is available

REM --- Create directories ---
echo.
echo [1/6] Creating directories...
if not exist "%EDLDIR%" mkdir "%EDLDIR%"
if not exist "%FILESDIR%" mkdir "%FILESDIR%"
if not exist "%DLSDIR%" mkdir "%DLSDIR%"
echo [OK] Directories ready

REM --- Clone edl tool ---
echo.
echo [2/6] Installing EDL tool...
if not exist "%EDLDIR%\edl.py" (
    git clone https://github.com/bkerler/edl.git "%EDLDIR%"
    if errorlevel 1 (
        echo [ERROR] Failed to clone edl tool.
        pause
        exit /b 1
    )
)
cd /d "%EDLDIR%"
python -m pip install --upgrade pip >nul 2>&1
python -m pip install -r requirements.txt
if errorlevel 1 (
    echo [ERROR] Failed to install Python dependencies.
    pause
    exit /b 1
)
echo [OK] EDL tool installed

REM --- Download OpenStick files ---
echo.
echo [3/6] Downloading OpenStick kernel and rootfs...
if not exist "%FILESDIR%\boot-ufi001c.img" (
    echo   - Kernel (~13 MB)
    curl -L -o "%FILESDIR%\boot-ufi001c.img" ^
        "https://github.com/OpenStick/OpenStick/releases/download/v1/boot-ufi001c.img"
)
if not exist "%DLSDIR%\debian.zip" (
    echo   - Debian rootfs (~360 MB) - this may take a while
    curl -L -o "%DLSDIR%\debian.zip" ^
        "https://github.com/OpenStick/OpenStick/releases/download/v1/debian.zip"
)
echo [OK] OpenStick files downloaded

REM --- Download DragonBoard bootloader ---
echo.
echo [4/6] Downloading DragonBoard bootloader...
if not exist "%DLSDIR%\db-bootloader.zip" (
    echo   - DragonBoard 410c bootloader (~8 MB)
    curl -L -o "%DLSDIR%\db-bootloader.zip" ^
        "https://storage.lavacloud.io/artifacts/dragonboard-410c/dragonboard-410c-bootloader-emmc-linux-176.zip"
)
echo [OK] Bootloader downloaded

REM --- Download prebuilt lk2nd ---
echo.
echo [5/6] Downloading prebuilt lk2nd...
if not exist "%DLSDIR%\prebuilt.zip" (
    curl -L -o "%DLSDIR%\prebuilt.zip" ^
        "https://gist.github.com/kinsamanka/0b01cd02412bd13ee072072043d46fa2/raw/prebuilt.zip"
)
echo [OK] lk2nd downloaded

REM --- Extract files ---
echo.
echo [6/6] Extracting files...
if not exist "%FILESDIR%\rootfs.img" (
    echo   - Debian rootfs
    powershell -Command "Expand-Archive -Path '%DLSDIR%\debian.zip' -DestinationPath '%DLSDIR%\db-extract' -Force"
    move "%DLSDIR%\db-extract\debian\rootfs.img" "%FILESDIR%\rootfs.img" >nul
)
if not exist "%FILESDIR%\sbl1.mbn" (
    echo   - DragonBoard bootloader
    powershell -Command "Expand-Archive -Path '%DLSDIR%\db-bootloader.zip' -DestinationPath '%DLSDIR%\db-extract' -Force"
    move "%DLSDIR%\db-extract\dragonboard-410c-bootloader-emmc-linux-176\sbl1.mbn" "%FILESDIR%\" >nul
    move "%DLSDIR%\db-extract\dragonboard-410c-bootloader-emmc-linux-176\rpm.mbn" "%FILESDIR%\" >nul
    move "%DLSDIR%\db-extract\dragonboard-410c-bootloader-emmc-linux-176\tz.mbn" "%FILESDIR%\" >nul
    move "%DLSDIR%\db-extract\dragonboard-410c-bootloader-emmc-linux-176\hyp.mbn" "%FILESDIR%\" >nul
    move "%DLSDIR%\db-extract\dragonboard-410c-bootloader-emmc-linux-176\sbc_1.0_8016.bin" "%FILESDIR%\" >nul
    move "%DLSDIR%\db-extract\dragonboard-410c-bootloader-emmc-linux-176\gpt_both0.bin" "%FILESDIR%\" >nul
)
if not exist "%FILESDIR%\emmc_appsboot-test-signed.mbn" (
    echo   - lk2nd bootloader
    powershell -Command "Expand-Archive -Path '%DLSDIR%\prebuilt.zip' -DestinationPath '%FILESDIR%' -Force"
)
echo [OK] Files extracted

REM --- Prepare GPT patch via WSL ---
echo.
echo Running GPT preparation in WSL...
wsl bash -c "cd /mnt/c/$(echo %WORKDIR% | sed 's|C:\\|c/|; s|\\|/|g') && chmod +x prep.sh && ./prep.sh"
if errorlevel 1 (
    echo [WARN] prep.sh failed. You may need to run it manually in WSL.
)

echo.
echo ============================================================
echo  SETUP COMPLETE
echo ============================================================
echo.
echo Next steps:
echo   1. Put your JZ01-45-@ into EDL mode
echo      - Hold the reset button while plugging USB
echo      - Verify "Qualcomm HS-USB QDLoader 9008" appears in Device Manager
echo   2. Run:  flash_edl.bat
echo.
echo Files are in: %FILESDIR%
echo.
pause
```

---

## 📄 3. `prep.sh` (WSL — GPT Patcher)

```bash
#!/bin/bash
# ============================================================
#  prep.sh - Patch GPT for JZ01-45-@ (fixes V33 disk-size mismatch)
#  Run in WSL from the installer directory
# ============================================================

set -e

# Resolve script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

FILES_DIR="files"
OUT_DIR="output"
mkdir -p "$OUT_DIR"

# Device disk size (from @ hardware, 0x738000 sectors)
DISK_SECTORS=0x738000

echo "=== JZ01-45-@ GPT Preparation ==="
echo "Working directory: $SCRIPT_DIR"
echo "Disk sectors: $DISK_SECTORS"
echo ""

# --- If GPT files don't exist yet, create placeholder ---
if [ ! -f "dumps/gpt_main0.bin" ]; then
    echo "[WARN] dumps/gpt_main0.bin not found"
    echo "       The script will use the OpenStick gpt_both0.bin as source"
    GPT_SRC="$FILES_DIR/gpt_both0.bin"
else
    GPT_SRC="dumps/gpt_main0.bin"
fi

# --- Patch main GPT ---
echo "[1/2] Patching main GPT..."
python3 <<PYEOF
import struct, zlib, os, sys

DISK_SECTORS = 0x738000
src = "$GPT_SRC"
dst = "$OUT_DIR/gpt_main_fixed.bin"

if not os.path.exists(src):
    print(f"ERROR: {src} not found")
    sys.exit(1)

with open(src, "rb") as f:
    data = bytearray(f.read())

# If input is gpt_both0.bin (OpenStick), it's 34 sectors
# If input is dumps/gpt_main0.bin, it might be truncated - pad to 34
full_size = 34 * 512
if len(data) < full_size:
    data.extend(b"\x00" * (full_size - len(data)))

HDR = 512
ENTRIES_OFF = 1024
NUM_ENTRIES = 128
ENTRY_SIZE = 128
entries_size = NUM_ENTRIES * ENTRY_SIZE

# Set backup GPT location = last sector
struct.pack_into("<Q", data, HDR + 32, DISK_SECTORS - 1)

# Set last usable LBA = last sector - 33
struct.pack_into("<Q", data, HDR + 48, DISK_SECTORS - 34)

# Recompute entries CRC
entries = bytes(data[ENTRIES_OFF:ENTRIES_OFF + entries_size])
entry_crc = zlib.crc32(entries) & 0xffffffff
struct.pack_into("<I", data, HDR + 88, entry_crc)

# Recompute header CRC
struct.pack_into("<I", data, HDR + 16, 0)
header = bytes(data[HDR:HDR + 92])
header_crc = zlib.crc32(header) & 0xffffffff
struct.pack_into("<I", data, HDR + 16, header_crc)

with open(dst, "wb") as f:
    f.write(data)
print(f"  Written: {dst} ({len(data)} bytes)")
print(f"  Backup LBA: 0x{DISK_SECTORS - 1:X}")
print(f"  Last usable LBA: 0x{DISK_SECTORS - 34:X}")
PYEOF

# --- Patch backup GPT ---
echo "[2/2] Patching backup GPT..."
python3 <<PYEOF
import struct, zlib, os

DISK_SECTORS = 0x738000
main_file = "$OUT_DIR/gpt_main_fixed.bin"
dst = "$OUT_DIR/gpt_backup_fixed.bin"

with open(main_file, "rb") as f:
    main = bytearray(f.read())

hdr = bytearray(main[512:512+512])
entries = bytes(main[1024:1024+16384])

# Adjust backup header
struct.pack_into("<Q", hdr, 24, DISK_SECTORS - 1)     # My LBA
struct.pack_into("<Q", hdr, 32, 0)                     # Alternate LBA (main)
struct.pack_into("<Q", hdr, 72, DISK_SECTORS - 33)     # Entry array LBA

# Recompute header CRC
struct.pack_into("<I", hdr, 16, 0)
struct.pack_into("<I", hdr, 16, zlib.crc32(bytes(hdr[:92])) & 0xffffffff)

# Compose backup file: 32 sectors entries + 1 sector header = 33 sectors
out = bytearray(33 * 512)
out[0:16384] = entries
out[16384:16384+512] = hdr

with open(dst, "wb") as f:
    f.write(out)
print(f"  Written: {dst} ({len(out)} bytes)")
PYEOF

echo ""
echo "=== GPT Preparation Complete ==="
echo "Patched GPT files in: $OUT_DIR"
echo ""
echo "Next: run flash_edl.bat (from Windows) with the dongle in EDL mode"
```

---

## 📄 4. `flash_edl.bat` (Windows Flash Sequence)

```batch
@echo off
REM ============================================================
REM  flash_edl.bat - Flash OpenStick to JZ01-45-@ via EDL
REM  Run as Administrator with dongle in EDL mode
REM ============================================================

setlocal enabledelayedexpansion

set WORKDIR=%~dp0
set EDLDIR=%WORKDIR%edl
set FILESDIR=%WORKDIR%files
set OUTFILE=%WORKDIR%output
set PYTHON=python

echo.
echo ============================================================
echo  JZ01-45-@ OpenStick Flasher
echo ============================================================
echo.

REM --- Verify EDL connection ---
echo [1/7] Verifying EDL connection...
%PYTHON% "%EDLDIR%\edl.py" printgpt --memory=eMMC
if errorlevel 1 (
    echo.
    echo [ERROR] Device not detected in EDL mode.
    echo.
    echo   1. Unplug the dongle
    echo   2. Hold the reset/EDL button
    echo   3. Plug in USB while holding
    echo   4. Release after 5 seconds
    echo   5. Verify "Qualcomm HS-USB QDLoader 9008" in Device Manager
    pause
    exit /b 1
)
echo [OK] Device in EDL mode

REM --- Backup current firmware ---
echo.
echo [2/7] Backing up current firmware...
if not exist "%WORKDIR%orig_fw" mkdir "%WORKDIR%orig_fw"

set BACKUP_FILE=%WORKDIR%orig_fw\orig_fw_%DATE:~-4%%DATE:~4,2%%DATE:~7,2%.bin
echo   Saving to: !BACKUP_FILE!
echo   (This takes 15-20 minutes, ~3.9 GB)

%PYTHON% "%EDLDIR%\edl.py" rf "!BACKUP_FILE!"
if errorlevel 1 (
    echo [ERROR] Firmware backup failed.
    pause
    exit /b 1
)
echo [OK] Backup saved

REM --- Backup OEM partitions ---
echo.
echo [3/7] Backing up OEM calibration partitions...
for %%P in (modemst1 modemst2 persist fsg fsc sec) do (
    echo   - %%P
    %PYTHON% "%EDLDIR%\edl.py" r %%P "%WORKDIR%orig_fw\%%P.bin" --memory=eMMC
    if errorlevel 1 (
        echo [WARN] Failed to back up %%P (continuing)
    )
)
echo [OK] OEM partitions backed up

REM --- Flash GPT (patched for @) ---
echo.
echo [4/7] Flashing patched GPT...
if exist "%OUTFILE%\gpt_main_fixed.bin" (
    %PYTHON% "%EDLDIR%\edl.py" ws 0 "%OUTFILE%\gpt_main_fixed.bin" --memory=eMMC
    if errorlevel 1 goto :fail
    %PYTHON% "%EDLDIR%\edl.py" ws 7569375 "%OUTFILE%\gpt_backup_fixed.bin" --memory=eMMC
    if errorlevel 1 goto :fail
) else (
    echo [ERROR] Patched GPT files not found in %OUTFILE%
    echo         Run install.bat first.
    pause
    exit /b 1
)
echo [OK] GPT flashed

REM --- Flash bootloader chain ---
echo.
echo [5/7] Flashing bootloader chain...
for %%P in (sbl1 rpm tz hyp aboot abootbak) do (
    if exist "%FILESDIR%\%%P.mbn" (
        echo   - %%P
        %PYTHON% "%EDLDIR%\edl.py" w %%P "%FILESDIR%\%%P.mbn" --memory=eMMC
        if errorlevel 1 goto :fail
    )
)
REM CDT
if exist "%FILESDIR%\sbc_1.0_8016.bin" (
    echo   - cdt
    %PYTHON% "%EDLDIR%\edl.py" w cdt "%FILESDIR%\sbc_1.0_8016.bin" --memory=eMMC
)
REM lk2nd to aboot/abootbak
%PYTHON% "%EDLDIR%\edl.py" w aboot "%FILESDIR%\emmc_appsboot-test-signed.mbn" --memory=eMMC
%PYTHON% "%EDLDIR%\edl.py" w abootbak "%FILESDIR%\emmc_appsboot-test-signed.mbn" --memory=eMMC
echo [OK] Bootloader flashed

REM --- Reboot to fastboot ---
echo.
echo [6/7] Rebooting to lk2nd fastboot...
%PYTHON% "%EDLDIR%\edl.py" e boot --memory=eMMC
%PYTHON% "%EDLDIR%\edl.py" reset
echo.
echo   Waiting for device to enter fastboot...
timeout /t 15 /nobreak >nul
fastboot devices
if errorlevel 1 (
    echo [ERROR] Device didn't enter fastboot.
    pause
    exit /b 1
)
echo [OK] Device in fastboot

REM --- Flash OpenStick via fastboot ---
echo.
echo [7/7] Flashing OpenStick (boot + rootfs)...
echo   This takes ~4 minutes for the rootfs...

fastboot flash partition "%FILESDIR%\gpt_both0.bin"
if errorlevel 1 goto :fail

fastboot flash sbl1 "%FILESDIR%\sbl1.mbn"
fastboot flash rpm "%FILESDIR%\rpm.mbn"
fastboot flash tz "%FILESDIR%\tz.mbn"
fastboot flash hyp "%FILESDIR%\hyp.mbn"
fastboot flash cdt "%FILESDIR%\sbc_1.0_8016.bin"
fastboot flash aboot "%FILESDIR%\emmc_appsboot-test-signed.mbn"
fastboot flash boot "%FILESDIR%\boot-ufi001c.img"

echo   - Writing rootfs (this takes a few minutes)...
fastboot flash rootfs "%FILESDIR%\rootfs.img"
if errorlevel 1 goto :fail

REM --- Restore OEM calibration ---
echo.
echo Restoring OEM calibration partitions...
fastboot flash sec "%WORKDIR%orig_fw\sec.bin"
fastboot flash fsc "%WORKDIR%orig_fw\fsc.bin"
fastboot flash fsg "%WORKDIR%orig_fw\fsg.bin"
fastboot flash modemst1 "%WORKDIR%orig_fw\modemst1.bin"
fastboot flash modemst2 "%WORKDIR%orig_fw\modemst2.bin"

REM --- Reboot ---
echo.
echo Rebooting to Debian...
fastboot reboot

echo.
echo ============================================================
echo  FLASH COMPLETE
echo ============================================================
echo.
echo First boot takes 2-3 minutes.
echo.
echo Next steps:
echo   1. Wait 3 minutes
echo   2. Find your dongle's IP (check router or use nmap)
echo   3. SSH in:  ssh root@^<dongle-ip^>
echo   4. Password: openstick
echo   5. Run:  bash post_config.sh
echo.
pause
exit /b 0

:fail
echo.
echo ============================================================
echo  FLASH FAILED
echo ============================================================
echo.
echo Your original firmware is backed up at:
echo   %WORKDIR%orig_fw\
echo.
echo To restore Android:
echo   edl wf "%WORKDIR%orig_fw\orig_fw_*.bin" --memory=eMMC
echo   edl reset
echo.
pause
exit /b 1
```

---

## 📄 5. `post_config.sh` (On-Device Configuration)

```bash
#!/bin/bash
# ============================================================
#  post_config.sh - Configure OpenStick after first boot
#  Run on the dongle: bash post_config.sh
# ============================================================

set -e

echo "=== JZ01-45-@ OpenStick Post-Install Configuration ==="
echo ""

# --- Verify we're on OpenStick ---
if ! grep -q "Debian" /etc/os-release; then
    echo "[ERROR] This doesn't look like Debian. Aborting."
    exit 1
fi
echo "[OK] Debian detected"

# --- Set root password ---
echo ""
echo "Set root password:"
passwd root

# --- Set hostname ---
echo ""
echo "Setting hostname to 'openstick'..."
hostnamectl set-hostname openstick

# --- Configure WiFi ---
echo ""
read -p "Enter your WiFi SSID: " WIFI_SSID
read -sp "Enter your WiFi password: " WIFI_PASS
echo ""

nmcli device wifi connect "$WIFI_SSID" password "$WIFI_PASS"
sleep 3

if ping -c 2 8.8.8.8 >/dev/null 2>&1; then
    echo "[OK] WiFi connected, internet works"
else
    echo "[WARN] No internet yet. Check WiFi credentials."
fi

# --- Fix apt sources ---
echo ""
echo "Fixing apt sources (archive mirrors)..."
cat > /etc/apt/sources.list << 'EOF'
deb http://mirrors.163.com/debian bullseye main contrib non-free
deb http://mirrors.163.com/debian bullseye-updates main contrib non-free
deb http://archive.debian.org/debian-security bullseye-security main contrib non-free
EOF

# Disable APT date check (Debian bullseye is EOL)
echo 'Acquire::Check-Valid-Until "false";' > /etc/apt/apt.conf.d/99no-check-valid-until

apt update
echo "[OK] APT sources fixed"

# --- Install useful tools ---
echo ""
echo "Installing useful packages..."
apt install -y \
    htop tmux nano curl git python3 python3-pip \
    iproute2 iw wireless-tools wpasupplicant \
    dnsmasq evtest

echo "[OK] Packages installed"

# --- Configure SSH ---
echo ""
echo "Enabling SSH root login..."
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
systemctl restart ssh
echo "[OK] SSH configured"

# --- Configure LEDs ---
echo ""
echo "Configuring LED triggers..."
cat > /etc/systemd/system/led-config.service << 'EOF'
[Unit]
Description=Configure status LEDs
After=multi-user.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/bash -c 'echo phy1tx > /sys/class/leds/blue:wifi/trigger 2>/dev/null || true'
ExecStart=/bin/bash -c 'echo usb-gadget > /sys/class/leds/green:internet/trigger 2>/dev/null || true'
ExecStart=/bin/bash -c 'echo heartbeat > /sys/class/leds/red:os/trigger 2>/dev/null || true'

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now led-config.service
echo "[OK] LEDs configured"

# --- Reset button handler ---
echo ""
echo "Setting up reset button (KEY_RESTART -> graceful shutdown)..."
cat > /usr/local/bin/reset-button-listener.py << 'PYEOF'
#!/usr/bin/env python3
import struct, subprocess, sys

EVENT_DEV = "/dev/input/event0"
KEY_RESTART = 408

def main():
    print("Listening on", EVENT_DEV)
    with open(EVENT_DEV, "rb") as f:
        while True:
            data = f.read(24)
            if len(data) < 24:
                break
            sec, usec, ev_type, ev_code, ev_val = struct.unpack("llHHI", data)
            if ev_type == 1 and ev_code == KEY_RESTART and ev_val == 1:
                subprocess.run(["/usr/bin/logger", "Reset button pressed"])
                # Change this to whatever action you want:
                subprocess.Popen(["/sbin/shutdown", "-h", "now"])

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(0)
PYEOF
chmod +x /usr/local/bin/reset-button-listener.py

cat > /etc/systemd/system/reset-listener.service << 'EOF'
[Unit]
Description=Reset button listener
After=multi-user.target

[Service]
Type=simple
ExecStart=/usr/local/bin/reset-button-listener.py
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now reset-listener.service
echo "[OK] Reset button configured"

# --- Display IP address ---
echo ""
echo "=== Configuration Complete ==="
echo ""
echo "Your dongle's IP addresses:"
ip addr show | grep -E "inet " | grep -v "127.0.0.1"
echo ""
echo "SSH access:  ssh root@<one-of-above-IPs>"
echo "Default password: (whatever you set earlier)"
echo ""
echo "Useful commands:"
echo "  systemctl status led-config"
echo "  systemctl status reset-listener"
echo "  ls /sys/class/leds/"
echo "  htop"
echo ""

# --- Optional: Disable IP conflict from USB RNDIS ---
echo "[INFO] If USB RNDIS interferes with WiFi, run:"
echo "       nmcli connection down USB"
echo ""
```

---

## 📄 6. `docs/RECOVERY.md`

```markdown
# Restoring Android to JZ01-45-@

If OpenStick breaks or you want Android back:

## Prerequisites

- Backup file: `orig_fw.bin` or `orig_fw_YYYYMMDD.bin` from `orig_fw/` folder
- Qualcomm USB drivers installed
- Dongle in EDL mode (9008)

## Restore Sequence

### 1. Enter EDL Mode
1. Unplug dongle from USB
2. Hold the reset/EDL button
3. Plug USB in while holding
4. Release after 5 seconds
5. Verify in Device Manager: `Qualcomm HS-USB QDLoader 9008`

### 2. Restore Full Firmware

    cd C:\jz01-openstick
    edl\edl.py wf orig_fw\orig_fw_YYYYMMDD.bin --memory=eMMC

Takes 15-20 minutes.

### 3. Restore GPT

    edl\edl.py ws 0 output\gpt_main_fixed.bin --memory=eMMC
    edl\edl.py ws 7569375 output\gpt_backup_fixed.bin --memory=eMMC

### 4. Restore OEM Partitions

    edl\edl.py w modemst1 orig_fw\modemst1.bin --memory=eMMC
    edl\edl.py w modemst2 orig_fw\modemst2.bin --memory=eMMC
    edl\edl.py w persist  orig_fw\persist.bin  --memory=eMMC
    edl\edl.py w fsg      orig_fw\fsg.bin      --memory=eMMC
    edl\edl.py w fsc      orig_fw\fsc.bin      --memory=eMMC
    edl\edl.py w sec      orig_fw\sec.bin      --memory=eMMC

### 5. Reset

    edl\edl.py reset

Unplug and replug USB. Wait 5-10 minutes for first boot.

## If It Doesn't Boot

1. Try a different USB port (prefer USB 2.0)
2. Re-run the `wf` command
3. Verify the backup file isn't corrupted (check size > 3 GB)
4. If GPT is bad, reflash only GPT (steps 3)
5. Post on XDA/4PDA with the exact error
```

---

## 📄 7. `docs/TROUBLESHOOTING.md`

```markdown
# Troubleshooting

## Device not detected in EDL mode

- Try a different USB cable (data-capable, not charge-only

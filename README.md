# JZ01-45-@ OpenStick Installer

One-click installer for running **Debian 11 (OpenStick)** on the
**JZ01-45-@** (MSM8916) 4G dongle.

**Tested on:** JZ01-45-@ hardware (eMMC: 0x738000 sectors)
**Result:** Working Debian 11 aarch64, root shell via ADB, WiFi client, SSH

---

## ⚠️ Read This First

- **This erases Android.** There is no dual-boot.
- **Backup required.** The installer saves your firmware to `orig_fw/`
  before flashing — copy it to external storage afterwards.
- **Only for JZ01-45-@** and compatible MSM8916 UFI dongles.
- **Not for V33.** V33 has a different eMMC size (0x760000) and won't
  fit on @ hardware without GPT surgery.
- **Cellular (SIM / 4G) will not work** — the V33-derived modemst
  partitions don't match @ hardware calibration.
- **Install to a path with no spaces**, e.g. `C:\jz01-openstick`.
- **Never edit the `.bat` files in Notepad while the folder is open.**
  Line endings get mangled and you end up with `pause@echo` corruption.

---

## 📋 Requirements

| Item | Notes |
|---|---|
| Windows 10/11 | Run `.bat` scripts as Administrator |
| Python 3.9+ | With "Add Python to PATH" checked |
| Git for Windows | https://git-scm.com/download/win |
| WSL2 with Ubuntu | Only used once, for GPT patching |
| Qualcomm USB Drivers | Or `libusb-win32` via Zadig (required for EDL) |
| ~10 GB free disk | Downloads + firmware backup |
| USB data cable | Not charge-only |

### Zadig setup (one time)

1. Enter EDL mode: unplug, hold reset, plug USB, release after 5 s
2. Open Zadig (run as Administrator)
3. **Options → List All Devices**
4. Select `QHSUSB_BULK` (USB ID `05C6 9008`)
5. Choose **`libusb-win32 (v1.2.7.3)`** as target driver
6. Click **Replace Driver**
7. Unplug and replug the device

Without this binding, `edl` will report `Device not found` or `LIBUSB_ERROR`.

---

## 🚀 Quick Start

### Step 1 — Prepare (Windows)

Run **`install.bat`** as Administrator. It will:

1. Check for Python, Git, WSL, and Administrator rights
2. Clone the `edl` tool + create a local venv
3. Download the OpenStick kernel (`boot-ufi001c.img`)
4. Download the Debian rootfs (`rootfs.img`, ~920 MB)
5. Download the DragonBoard 410c bootloader (`sbl1/rpm/tz/hyp/cdt`)
6. Download prebuilt lk2nd (`emmc_appsboot-test-signed.mbn`)
7. Patch the GPT via WSL (`prep.sh`)

**Download the Firehose loader manually** — the installer doesn't fetch it:

```bat
mkdir edl\Loaders\custom
curl -L -o edl\Loaders\custom\prog_emmc_firehose_8916.mbn ^
  https://raw.githubusercontent.com/OneLabsTools/Programmers/master/prog_emmc_firehose_8916.mbn

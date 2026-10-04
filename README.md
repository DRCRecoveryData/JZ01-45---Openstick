# JZ01-45-@ OpenStick Installer

One-click installer for running **Debian 11 (OpenStick)** on the
**JZ01-45-@** (MSM8916) 4G dongle.

**Tested on:** JZ01-45-@ hardware
**Result:** Working Debian 11 aarch64, WiFi client, SSH, LEDs, reset button

---

## ⚠️ Read This First

- **This will erase Android** from your dongle.
- **Backup required.** The installer saves your firmware to `orig_fw/`
  before flashing — copy it somewhere safe afterwards.
- **Only for JZ01-45-@** (or compatible MSM8916 UFI dongles).
- **Not for V33** — use kinsamanka's gist instead.
- Cellular (SIM) will **not work** unless you have proper IMEI/calibration
  data restored from your backup.
- **Install to a path with no spaces** (e.g. `C:\jz01-openstick`).

---

## 📋 Requirements

| Item | Notes |
|---|---|
| Windows 10/11 | Run the `.bat` scripts as Administrator |
| WSL2 with Ubuntu | `wsl --install -d Ubuntu` in PowerShell |
| Python 3.9+ | On Windows, with "Add Python to PATH" checked |
| Git for Windows | https://git-scm.com/download/win |
| Qualcomm USB Drivers | Or `libusb-win32` via Zadig |
| ~10 GB free disk | Downloads + firmware backup |
| USB data cable | Not charge-only |

---

## 🚀 Quick Start

### 1. Prepare (Windows)

Double-click **`install.bat`** (as Administrator). It will:

1. Check for Python, Git, WSL, and Administrator rights
2. Clone the `edl` tool and install its Python deps into a local venv
3. Download the OpenStick kernel + Debian rootfs
4. Download the DragonBoard 410c bootloader
5. Download prebuilt lk2nd
6. Extract everything into `files/`
7. Patch the GPT for the JZ01-45-@ disk size via WSL (`prep.sh`)

Result: `files/` and `output/` are populated and ready to flash.

### 2. Flash (Windows)

Put the dongle into **EDL mode**:

1. Unplug the dongle
2. Hold the reset/EDL button
3. Plug USB in while holding, release after ~5 seconds
4. Confirm `Qualcomm HS-USB QDLoader 9008` in Device Manager

Then double-click **`flash_edl.bat`** (as Administrator). It will:

1. Verify EDL connection
2. Back up your firmware to `orig_fw/orig_fw_YYYYMMDD.bin` (~3.9 GB)
3. Back up OEM calibration partitions (`modemst1`, `modemst2`, `persist`, `fsg`, `fsc`, `sec`)
4. Flash the patched GPT
5. Flash the bootloader chain (`sbl1`, `rpm`, `tz`, `hyp`, `cdt`, `aboot`, `abootbak`)
6. Restore OEM calibration partitions via EDL
7. `edl reset` → wait for lk2nd fastboot
8. `fastboot flash boot` + `fastboot flash rootfs`
9. `fastboot reboot` into Debian

First boot takes **2–3 minutes**.

### 3. Configure (from your PC)

```bash
ssh root@<dongle-ip>       # default password: openstick
bash post_config.sh
```

`post_config.sh` sets up:

- WiFi auto-connect (you supply SSID + password)
- SSH service on port 22
- LED triggers (WiFi activity, USB gadget, heartbeat)
- Reset button as graceful shutdown
- Apt archive mirrors (Debian bullseye is EOL)

---

## 📁 Repo Layout

| Path | Purpose |
|---|---|
| [`install.bat`](install.bat) | Windows master installer |
| [`prep.sh`](prep.sh) | WSL-side GPT patcher |
| [`flash_edl.bat`](flash_edl.bat) | EDL + fastboot flash sequence |
| [`post_config.sh`](post_config.sh) | On-device configuration |
| [`docs/RECOVERY.md`](docs/RECOVERY.md) | Restore Android |
| [`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md) | Common issues |
| `files/` | Downloaded binaries *(gitignored)* |
| `output/` | Patched GPT files *(gitignored)* |
| `dl/` | Download cache *(gitignored)* |
| `edl/` | edl clone + venv *(gitignored)* |
| `orig_fw/` | Firmware backup *(gitignored)* |

---

## 💾 What Gets Installed

| Partition | Content |
|---|---|
| `aboot`, `abootbak` | lk2nd bootloader |
| `sbl1`, `rpm`, `tz`, `hyp` | DragonBoard 410c bootloader |
| `cdt` | DragonBoard CDT |
| `boot` | OpenStick kernel + DTB (`boot-ufi001c.img`) |
| `rootfs` | Debian 11 rootfs |
| `modemst1`, `modemst2` | **Preserved** — original IMEI |
| `persist` | **Preserved** — original WiFi MAC |
| `fsg`, `fsc`, `sec` | **Preserved** — calibration data |

---

## 🔑 Post-Install Defaults

| Setting | Value |
|---|---|
| Root password | `openstick` — change with `passwd` |
| WiFi | Client mode, connects to your home network |
| SSH | Enabled on port 22, root login allowed |
| Hostname | `openstick` |
| LEDs | WiFi TX / USB gadget / heartbeat |

---

## 🔄 Restoring Android

Full procedure in [`docs/RECOVERY.md`](docs/RECOVERY.md). Short version:

1. Put the dongle in EDL mode (see step 2 above).
2. From the repo root:

   ```bat
   edl\venv\Scripts\python edl\edl.py wf orig_fw\orig_fw_YYYYMMDD.bin --memory=eMMC
   edl\venv\Scripts\python edl\edl.py reset
   ```

3. Unplug, replug, wait 5–10 minutes for first Android boot.

---

## 🧯 If Something Breaks

See [`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md) for:

- Device not detected in EDL mode
- Fastboot not appearing after `edl reset`
- WiFi won't connect
- LEDs don't light up
- Reset button doesn't work
- SSH refused
- Apt update failures (bullseye EOL)
- Hard-brick recovery notes

---

## 📜 Credits

- **kinsamanka** — original OpenStick installation gist
- **bkerler** — `edl` tool for Qualcomm EDL
- **OpenStick project** — kernel and rootfs
- **96boards.org** — DragonBoard 410c bootloader

This repo is a streamlined repackaging with:

- Recovery steps for corrupted/bricked boards
- GPT patching for the JZ01-45-@ disk size
- Automated downloads (with venv-isolated Python deps)
- Post-install WiFi / LED / button configuration

---

## ⚖️ License

MIT — see [`LICENSE`](LICENSE). No warranty.

This is a hobby project. If something breaks, you're on your own — but
[`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md) covers the common cases.

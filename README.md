# JZ01-45-@ / JZ0145_V33 OpenStick Installer

One-click installer for running **Debian 11 (OpenStick)** on the
**JZ01-45-@** (a.k.a. **JZ0145_V33**) MSM8916 4G dongle.

**Tested on:** JZ0145_V33 hardware, eMMC size 0x738000 sectors
**Result:** Working Debian 11 aarch64, WiFi client, SSH, LEDs, reset button

---

## ⚠️ Read This First

- **This erases Android.** No dual-boot.
- **Backup is automatic** — the installer saves the full eMMC to
  `orig_fw/` before flashing. Copy it to external storage afterwards.
- **Works on both eMMC sizes** — 0x738000 (3.6 GB) and 0x760000 (3.9 GB).
  The installer detects and patches the GPT for the smaller eMMC.
- **Cellular (SIM / 4G) will not work** unless you have valid IMEI
  calibration. The default install uses whatever modemst was on the
  device.
- **Install to a path with no spaces**, e.g. `C:\jz01-openstick`.
- **Do not edit the `.bat` files in Notepad while a shell is open** —
  line endings get mangled. Use `make_flash.py` or Git Bash.

---

## 📋 Requirements

| Item | Notes |
|---|---|
| Windows 10/11 | Run `.bat` scripts as Administrator |
| Python 3.9+ | With "Add Python to PATH" checked |
| Git for Windows | https://git-scm.com/download/win |
| WSL2 with Ubuntu | Only for GPT patching via `prep.sh` |
| Qualcomm USB Drivers | Or `libusb-win32` via Zadig (required) |
| ~10 GB free disk | Downloads + firmware backup |
| USB data cable | Not charge-only |

### Zadig setup (once)

1. Enter EDL mode: unplug → hold reset → plug USB → release after 5 s
2. Open Zadig as Administrator
3. **Options → List All Devices**
4. Select `QHSUSB_BULK` (USB ID `05C6 9008`)
5. Choose **`libusb-win32 (v1.2.7.3)`**
6. Click **Replace Driver**
7. Unplug and replug

Without this binding, `edl` reports `LIBUSB_ERROR` or `Device not found`.

---

## 🚀 Quick Start

### Step 1 — Prepare

Run **`install.bat`** as Administrator. It will:

1. Check Python, Git, WSL, Administrator rights
2. Clone `edl` + create a venv
3. Download OpenStick kernel + Debian rootfs
4. Download DragonBoard 410c bootloader
5. Download prebuilt lk2nd
6. Download Firehose loader (`prog_emmc_firehose_8916.mbn`)
7. Patch base GPT via WSL
8. **Patch rootfs size** (`fix_gpt.py`)
9. **Patch DTB LED/reset/SIM pins** (`fix_dtb_inplace.py`)

Result: `files/` and `output/` populated with patched images.

### Step 2 — Enter EDL mode

1. Unplug the dongle
2. Hold the reset/EDL button
3. Plug USB in while holding
4. Release after 5 seconds
5. Verify `QHSUSB_BULK` in Device Manager

### Step 3 — Flash

Run **`flash_edl.bat`** as Administrator. It will:

1. Verify EDL connection
2. Back up current firmware (~3.9 GB, 15–20 min)
3. Write patched main + backup GPT
4. Write bootloader chain (sbl1, rpm, tz, hyp, cdt)
5. Write lk2nd to aboot
6. Write OpenStick kernel (with patched DTB) to boot
7. Write Debian rootfs

Total: ~25 minutes.

### Step 4 — Reboot

1. Unplug USB
2. Wait **60 seconds**
3. Plug in plain USB — **do not touch reset**
4. Wait 2–3 minutes

**`edl reset` does not work on this hardware.** The loader has a
sector-size XML bug. Physical replug is the only reliable exit from EDL.

### Step 5 — Configure

```bat
adb wait-for-device
adb push post_config.sh /root/post_config.sh
adb shell
```

On device:

```bash
cd /root && chmod +x post_config.sh && bash post_config.sh
```

You'll be asked for:
- A root password
- Your WiFi SSID + password

The script configures:
- WiFi auto-connect via NetworkManager
- SSH on port 22 (root login allowed)
- LED triggers (WiFi TX, USB gadget, heartbeat)
- Reset button → graceful shutdown
- Debian archive mirrors (bullseye is EOL)

---

## 📁 Repo Layout

| Path | Purpose |
|---|---|
| `install.bat` | Downloads binaries, sets up edl venv |
| `prep.sh` | WSL-side GPT patcher (base template) |
| `fix_gpt.py` | Resizes `rootfs` partition in GPT |
| `fix_dtb_inplace.py` | Patches LED/reset/SIM pins in boot.img DTB |
| `flash_edl.bat` | EDL flash sequence |
| `post_config.sh` | On-device configuration |
| `make_flash.py` | Helper to regenerate flash_edl.bat cleanly |
| `files/` | Downloaded + patched binaries *(gitignored)* |
| `output/` | Patched GPT files *(gitignored)* |
| `edl/` | edl clone + venv *(gitignored)* |
| `orig_fw/` | Firmware backups *(gitignored)* |

---

## 💾 What Gets Installed

| Partition | Content |
|---|---|
| `sbl1`, `rpm`, `tz`, `hyp` | DragonBoard 410c bootloader |
| `cdt` | DragonBoard CDT |
| `aboot` | lk2nd (open bootloader) |
| `boot` | OpenStick kernel + **patched** DTB |
| `rootfs` | Debian 11 aarch64 |
| `modemst1/2`, `fsg`, `fsc`, `sec`, `persist` | Untouched |

---

## 🔑 Post-Install Defaults

| Setting | Value |
|---|---|
| Root password | (set during post_config) |
| Hostname | `openstick` |
| ADB serial | `0123456789` |
| SSH | port 22, root login |
| WiFi | client mode |
| LEDs | blue=WiFi TX, green=USB, red=heartbeat |
| Reset button | graceful shutdown |

---

## 🔧 Hardware-Specific Notes

### Board identity

The silkscreen **`JZ0145_V33`** and the sticker **`JZ01-45-@`** refer to
the same board. Only the eMMC size varies between production batches:

| Batch | eMMC sectors | Size |
|---|---|---|
| Small | `0x738000` | 3,875,536,896 bytes |
| Large | `0x760000` | 3,959,422,976 bytes |

The installer detects the physical disk and shrinks the `rootfs` GPT
entry to match.

### LED / reset / SIM pins

The base OpenStick DTB points LEDs at GPIO 20/21/22 — **wrong for
JZ0145_V33**. Real hardware:

| Function | Correct GPIO |
|---|---|
| Blue LED (wifi) | **GPIO 7** |
| Green LED (internet) | **GPIO 6** |
| Red LED (os) | **GPIO 8** |
| Reset button | **GPIO 37** |
| SIM enable | GPIO 20, 22 |
| SIM select | GPIO 1, 23 |

`fix_dtb_inplace.py` patches these pins inside the DTB that's appended
to the OpenStick kernel (`Image.gz-dtb` format). It edits bytes
in-place so the gzip stream stays byte-identical and the boot image
remains the exact same size.

### Reset button key code

The button emits `KEY_F1` (code **59**), not `KEY_RESTART` (408). The
`post_config.sh` listener uses the correct code.

---

## 🧯 Troubleshooting

- **Not detected in EDL** — re-check Zadig binding, try a different
  USB port, use a data-capable cable
- **Writes fail partway** — re-run the same `edl w` command; edl is
  idempotent
- **Stuck in fastboot** — device fell back from a bad boot.img. Recover
  with EDL:
  ```bat
  edl\venv\Scripts\python edl\edl.py --loader edl\Loaders\custom\prog_emmc_firehose_8916.mbn w boot files\boot-ufi001c.img --memory=eMMC
  ```
- **Boots but no network** — check `ip addr` via `adb shell`. If
  `wlan0` missing, run `bash /root/post_config.sh`
- **LEDs don't light** — check
  ```bash
  od -A x -t x1z /proc/device-tree/leds/wifi/gpios
  ```
  should show GPIO 7. If 20, DTB patch didn't take.

---

## 📜 Credits

- **kinsamanka** — original OpenStick gist, `patch.dts` for JZ0145_V33
- **bkerler** — `edl` tool
- **OpenStick project** — kernel and rootfs
- **96boards.org** — DragonBoard bootloader

---

## ⚖️ License

MIT — see [`LICENSE`](LICENSE). No warranty.

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

#!/bin/bash
# ============================================================
#  prep.sh - Patch GPT for JZ01-45-@ (fixes V33 disk-size mismatch)
#  Run from WSL, in the repo directory.
# ============================================================

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

FILES_DIR="files"
OUT_DIR="output"
mkdir -p "$OUT_DIR"

# Disk sectors for JZ01-45-@ eMMC (~3.7 GiB)
DISK_SECTORS=0x738000

echo "=== JZ01-45-@ GPT Preparation ==="
echo "Working directory: $SCRIPT_DIR"
echo "Disk sectors:      $DISK_SECTORS"
echo ""

# Prefer a real dump if available; otherwise use gpt_both0.bin as template.
if [ -f "dumps/gpt_main0.bin" ]; then
    GPT_SRC="dumps/gpt_main0.bin"
    echo "[INFO] Using dumps/gpt_main0.bin as template"
else
    GPT_SRC="$FILES_DIR/gpt_both0.bin"
    echo "[INFO] Using $GPT_SRC as template"
fi

if [ ! -f "$GPT_SRC" ]; then
    echo "[ERROR] GPT source not found: $GPT_SRC"
    echo "        Run install.bat first (extracts gpt_both0.bin),"
    echo "        or place a device dump at dumps/gpt_main0.bin."
    exit 1
fi

echo "[1/2] Patching main GPT..."
python3 - "$GPT_SRC" "$OUT_DIR/gpt_main_fixed.bin" "$DISK_SECTORS" <<'PYEOF'
import struct, zlib, os, sys

src, dst, sectors = sys.argv[1], sys.argv[2], int(sys.argv[3], 0)

with open(src, "rb") as f:
    data = bytearray(f.read())

HDR = 512
ENTRIES_OFF = 1024
NUM_ENTRIES = 128
ENTRY_SIZE = 128
entries_size = NUM_ENTRIES * ENTRY_SIZE

full_size = 34 * 512
if len(data) < full_size:
    data.extend(b"\x00" * (full_size - len(data)))
elif len(data) > full_size:
    # gpt_both0.bin is 34 sectors; keep only the main header + entries.
    data = data[:full_size]

# Sanity check signature
if data[HDR:HDR+8] != b"EFI PART":
    print("ERROR: missing EFI PART signature at offset 512", file=sys.stderr)
    sys.exit(1)

# Partition entry array LBA (standard: 2)
struct.pack_into("<Q", data, HDR + 72, 2)

# Backup GPT location = last sector
struct.pack_into("<Q", data, HDR + 32, sectors - 1)

# Last usable LBA = last sector - 33
struct.pack_into("<Q", data, HDR + 48, sectors - 34)

# Recompute entries CRC
entries = bytes(data[ENTRIES_OFF:ENTRIES_OFF + entries_size])
struct.pack_into("<I", data, HDR + 88, zlib.crc32(entries) & 0xffffffff)

# Recompute header CRC (zero it first)
struct.pack_into("<I", data, HDR + 16, 0)
header = bytes(data[HDR:HDR + 92])
struct.pack_into("<I", data, HDR + 16, zlib.crc32(header) & 0xffffffff)

with open(dst, "wb") as f:
    f.write(data)

print(f"  Written: {dst} ({len(data)} bytes)")
print(f"  Backup LBA:      0x{sectors - 1:X}")
print(f"  Last usable LBA: 0x{sectors - 34:X}")
PYEOF

echo "[2/2] Patching backup GPT..."
python3 - "$OUT_DIR/gpt_main_fixed.bin" "$OUT_DIR/gpt_backup_fixed.bin" "$DISK_SECTORS" <<'PYEOF'
import struct, zlib, sys

main_file, dst, sectors = sys.argv[1], sys.argv[2], int(sys.argv[3], 0)

with open(main_file, "rb") as f:
    main = bytearray(f.read())

hdr = bytearray(main[512:512+512])
entries = bytes(main[1024:1024+16384])

# Backup header layout:
#   MyLBA         (offset 24) = last sector
#   AlternateLBA  (offset 32) = 0 (main header's location)
#   PartitionEntryLBA (offset 72) = sectors - 33
struct.pack_into("<Q", hdr, 24, sectors - 1)
struct.pack_into("<Q", hdr, 32, 0)
struct.pack_into("<Q", hdr, 72, sectors - 33)

# Recompute header CRC
struct.pack_into("<I", hdr, 16, 0)
struct.pack_into("<I", hdr, 16, zlib.crc32(bytes(hdr[:92])) & 0xffffffff)

# 32 sectors of entries + 1 sector of header
out = bytearray(33 * 512)
out[0:16384] = entries
out[16384:16384+512] = hdr

with open(dst, "wb") as f:
    f.write(out)

print(f"  Written: {dst} ({len(out)} bytes)")
PYEOF

echo ""
echo "=== GPT Preparation Complete ==="
echo "Patched files in: $OUT_DIR/"
echo "Next: run flash_edl.bat (Windows) with the dongle in EDL mode."

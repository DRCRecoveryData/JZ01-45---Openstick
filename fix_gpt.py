# fix_gpt.py - resize rootfs partition in the OpenStick GPT to fit the smaller eMMC
import struct, zlib, os

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "output", "gpt_main_fixed.bin")
DST_MAIN = os.path.join(HERE, "output", "gpt_main_rootfs.bin")
DST_BAK  = os.path.join(HERE, "output", "gpt_backup_rootfs.bin")

DISK_SECTORS = 0x738000
HDR_OFF = 512
ENTRIES_OFF = 1024
ROOTFS_START = 0x8984c00 // 512
ROOTFS_END   = DISK_SECTORS - 34

if not os.path.isfile(SRC):
    raise SystemExit(f"missing {SRC} - run install.bat first")

with open(SRC, "rb") as f:
    data = bytearray(f.read())

if data[HDR_OFF:HDR_OFF+8] != b"EFI PART":
    raise SystemExit("no GPT signature")

num_entries = struct.unpack_from("<I", data, HDR_OFF + 80)[0]
entry_size  = struct.unpack_from("<I", data, HDR_OFF + 84)[0]

idx = None
for i in range(num_entries):
    off = ENTRIES_OFF + i * entry_size
    name = data[off+56:off+56+72].decode("utf-16-le").rstrip("\x00")
    if name == "rootfs":
        idx = i; break
if idx is None:
    raise SystemExit("rootfs not found")

off = ENTRIES_OFF + idx * entry_size
old_start = struct.unpack_from("<Q", data, off + 32)[0]
old_end   = struct.unpack_from("<Q", data, off + 40)[0]
print(f"old rootfs: start=0x{old_start:X} end=0x{old_end:X} sectors={old_end-old_start+1}")

struct.pack_into("<Q", data, off + 32, ROOTFS_START)
struct.pack_into("<Q", data, off + 40, ROOTFS_END)

entries = bytes(data[ENTRIES_OFF:ENTRIES_OFF + num_entries*entry_size])
struct.pack_into("<I", data, HDR_OFF + 88, zlib.crc32(entries) & 0xFFFFFFFF)
struct.pack_into("<I", data, HDR_OFF + 16, 0)
struct.pack_into("<I", data, HDR_OFF + 16, zlib.crc32(bytes(data[HDR_OFF:HDR_OFF+92])) & 0xFFFFFFFF)
open(DST_MAIN, "wb").write(data)
print(f"wrote {DST_MAIN} ({len(data)} bytes)")

backup = bytearray(33 * 512)
backup[0:num_entries*entry_size] = entries
bhdr = bytearray(data[HDR_OFF:HDR_OFF+512])
struct.pack_into("<Q", bhdr, 24, DISK_SECTORS - 1)
struct.pack_into("<Q", bhdr, 32, 1)
struct.pack_into("<Q", bhdr, 72, DISK_SECTORS - 33)
struct.pack_into("<I", bhdr, 16, 0)
struct.pack_into("<I", bhdr, 16, zlib.crc32(bytes(bhdr[:92])) & 0xFFFFFFFF)
backup[32*512:33*512] = bhdr
open(DST_BAK, "wb").write(backup)
print(f"wrote {DST_BAK} ({len(backup)} bytes)")
print(f"new rootfs: start=0x{ROOTFS_START:X} end=0x{ROOTFS_END:X} sectors={ROOTFS_END-ROOTFS_START+1}")

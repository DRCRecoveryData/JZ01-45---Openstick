#!/usr/bin/env python3
"""
fix_dtb_inplace.py - patch LED/reset/SIM pins in boot.img DTB.

The OpenStick kernel field is [gzip stream][raw DTB]. This script
edits ONLY the DTB bytes (uncompressed, in-place) and keeps the gzip
stream byte-identical. Output file size matches input exactly.

Fixes for JZ0145_V33 (per kinsamanka's patch.dts):
  LEDs:  GPIO 20/21/22  ->  7/6/8
  Reset: already 37
  SIM:   pins corrected to 1/20/22/23
"""
import hashlib
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
BOOT_SRC = os.path.join(HERE, "files", "boot-ufi001c.img")
BOOT_DST = os.path.join(HERE, "files", "boot-ufi001c-leds.img")

BOOT_MAGIC = b"ANDROID!"
HDR_SIZE = 8 + 40 + 16 + 512 + 32 + 1024
FDT_MAGIC = 0xd00dfeed
FDT_BEGIN_NODE = 1
FDT_END_NODE = 2
FDT_PROP = 3
FDT_NOP = 4
FDT_END = 9

PATCHES = {
    "leds/wifi":              {"gpios": (4, 7)},
    "leds/internet":          {"gpios": (4, 6)},
    "leds/os":                {"gpios": (4, 8)},
    "gpio-keys/reset":        {"gpios": (4, 37)},
    "gpio-keys/key_reset":    {"gpios": (4, 37)},
    "leds/sim_sel":           {"gpios": (4, 1)},
    "leds/sim_sel2":          {"gpios": (4, 20)},
    "leds/sim_en":            {"gpios": (4, 22)},
    "leds/sim_en2":           {"gpios": (4, 23)},
}

def log(m=""): print(m, flush=True)
def align(n, a): return (n + a - 1) // a * a

def read_cstr(d, o):
    e = d.index(b"\x00", o)
    return d[o:e].decode("ascii", "replace"), e + 1

def walk_fdt(d):
    (magic, totalsize, off_struct, off_strings, off_rsvmap,
     version, last_comp, boot_cpuid, size_str, size_struct) = \
        struct.unpack_from(">10I", d, 0)
    if magic != FDT_MAGIC:
        raise ValueError(f"bad FDT magic 0x{magic:08x}")
    strings = d[off_strings:off_strings + size_str]
    def rs(o):
        e = strings.index(b"\x00", o)
        return strings[o:e].decode("ascii", "replace")
    off = off_struct
    path = []
    while True:
        token = struct.unpack_from(">I", d, off)[0]
        off += 4
        if token == FDT_BEGIN_NODE:
            name, off = read_cstr(d, off)
            off = (off + 3) & ~3
            path.append(name)
        elif token == FDT_END_NODE:
            if path: path.pop()
        elif token == FDT_PROP:
            length, nameoff = struct.unpack_from(">II", d, off)
            off += 8
            name = rs(nameoff)
            voff = off
            off += (length + 3) & ~3
            yield ("/".join(p for p in path if p), name, voff, length)
        elif token == FDT_NOP:
            continue
        elif token == FDT_END:
            break
        else:
            raise ValueError(f"bad token {token}")

def patch_dtb(data, dtb_off):
    changed = 0
    for path, name, off, length in walk_fdt(bytes(data[dtb_off:dtb_off+200000])):
        if path not in PATCHES: continue
        if name not in PATCHES[path]: continue
        celloff, newval = PATCHES[path][name]
        if length < celloff + 4:
            log(f"  [WARN] {path}/{name} too short")
            continue
        absolute_off = dtb_off + off + celloff
        old = struct.unpack_from(">I", data, absolute_off)[0]
        if old == newval:
            log(f"  {path:22s} gpio {old} (already correct)")
            changed += 1
            continue
        struct.pack_into(">I", data, absolute_off, newval)
        log(f"  {path:22s} gpio {old} -> {newval}")
        changed += 1
    return changed

def main():
    if not os.path.isfile(BOOT_SRC):
        sys.exit(f"ERROR: {BOOT_SRC} not found")

    log(f"Reading {BOOT_SRC} ...")
    with open(BOOT_SRC, "rb") as f:
        raw = bytearray(f.read())

    if raw[:8] != BOOT_MAGIC:
        sys.exit("not an Android boot image")
    (kernel_size, kernel_addr,
     ramdisk_size, ramdisk_addr,
     second_size, second_addr,
     tags_addr, page_size,
     hv, ov) = struct.unpack_from("<10I", raw, 8)
    log(f"  page_size:   {page_size}")
    log(f"  kernel_size: {kernel_size}")
    log(f"  ramdisk_size:{ramdisk_size}")

    kernel_off = align(HDR_SIZE, page_size)
    kernel_end = kernel_off + kernel_size
    log(f"  kernel field: [{kernel_off}..{kernel_end}]")

    log("\nScanning for DTB inside kernel field ...")
    dtb_off = raw.find(b"\xd0\x0d\xfe\xed", kernel_off, kernel_end)
    if dtb_off < 0:
        sys.exit("ERROR: no FDT magic found in kernel field")

    dtb_size = struct.unpack_from(">I", raw, dtb_off + 4)[0]
    log(f"  DTB at offset {dtb_off}, size {dtb_size} bytes")

    if dtb_off + dtb_size > kernel_end:
        sys.exit("ERROR: DTB extends past kernel field")

    log("\nPatching DTB pins (in place, gzip untouched) ...")
    changed = patch_dtb(raw, dtb_off)
    log(f"  {changed} patches applied")

    log("\nRecomputing header SHA1 ...")
    kernel_bytes = bytes(raw[kernel_off:kernel_off + kernel_size])
    ramdisk_off = kernel_off + align(kernel_size, page_size)
    ramdisk_bytes = bytes(raw[ramdisk_off:ramdisk_off + ramdisk_size])
    second_off = ramdisk_off + align(ramdisk_size, page_size)
    second_bytes = bytes(raw[second_off:second_off + second_size])

    h = hashlib.sha1()
    h.update(kernel_bytes + struct.pack("<I", kernel_size))
    h.update(ramdisk_bytes + struct.pack("<I", ramdisk_size))
    h.update(second_bytes + struct.pack("<I", second_size))
    new_id = h.digest()

    id_off = 8 + 40 + 16 + 512
    raw[id_off:id_off + 32] = new_id.ljust(32, b"\x00")
    log(f"  id: {new_id.hex()}")

    log(f"\nOutput size: {len(raw)} bytes")
    log(f"Input  size: {os.path.getsize(BOOT_SRC)} bytes")

    if len(raw) != os.path.getsize(BOOT_SRC):
        sys.exit("ERROR: output size mismatch — refusing to write")

    with open(BOOT_DST, "wb") as f:
        f.write(raw)
    log(f"\nWrote {BOOT_DST}")

if __name__ == "__main__":
    main()

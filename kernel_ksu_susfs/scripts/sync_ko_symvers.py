#!/usr/bin/env python3
"""Sync __versions CRCs, vermagic, and optional MODULE_SIG on sony_carillon_nfc.ko
against a newly compiled Linux 4.9.186 kernel build directory (out_cxd224).
"""
import argparse
import os
import struct
import subprocess


def parse_symvers(symvers_path):
    syms = {}
    with open(symvers_path, "r", encoding="utf-8", errors="replace") as f:
        for line in f:
            parts = line.strip().split("\t")
            if len(parts) >= 2:
                crc = int(parts[0], 16)
                name = parts[1]
                syms[name] = crc
    return syms


def parse_utsrelease(uts_path):
    with open(uts_path, "r", encoding="utf-8") as f:
        for line in f:
            if "UTS_RELEASE" in line:
                return line.split('"')[1]
    raise RuntimeError(f"UTS_RELEASE not found in {uts_path}")


def patch_elf_ko(ko_in, ko_out, syms, new_vermagic):
    data = bytearray(open(ko_in, "rb").read())

    # Strip any trailing appended module signature if present
    sig_marker = b"~Module signature appended~\n"
    idx_sig = data.rfind(sig_marker)
    if idx_sig != -1 and idx_sig + len(sig_marker) == len(data):
        # 12-byte info struct immediately precedes marker: magic? No, 4*u8 + u32 + u32 = 12 bytes before marker
        sig_len, = struct.unpack_from(">I", data, idx_sig - 4)
        cut = idx_sig - 12 - sig_len
        if cut > 0:
            data = data[:cut]

    e_shoff, = struct.unpack_from("<Q", data, 40)
    e_shentsize, e_shnum, e_shstrndx = struct.unpack_from("<HHH", data, 58)

    def sh(idx):
        off = e_shoff + idx * e_shentsize
        return struct.unpack_from("<IIQQQQIIQQ", data, off)

    shstr_off = sh(e_shstrndx)[4]
    found_versions = False
    found_modinfo = False

    for i in range(e_shnum):
        s = sh(i)
        name_end = data.find(b"\x00", shstr_off + s[0])
        name = data[shstr_off + s[0]:name_end].decode("utf-8", errors="replace")
        sec_off, sec_sz = s[4], s[5]

        if name == "__versions":
            found_versions = True
            if sec_sz % 64 != 0:
                raise RuntimeError(f"Unexpected __versions size {sec_sz} (not multiple of 64)")
            updated = 0
            for j in range(0, sec_sz, 64):
                crc_old, sym_raw = struct.unpack_from("<Q56s", data, sec_off + j)
                sym_name = sym_raw.split(b"\x00", 1)[0].decode("utf-8")
                if sym_name not in syms:
                    raise RuntimeError(f"Missing kernel symbol in Module.symvers: {sym_name}")
                struct.pack_into("<Q", data, sec_off + j, syms[sym_name])
                updated += 1
            print(f"[sync_ko] Updated {updated} symbol CRCs in __versions")

        elif name == ".modinfo":
            found_modinfo = True
            modinfo = bytes(data[sec_off:sec_off + sec_sz])
            key = b"vermagic="
            pos = modinfo.find(key)
            if pos < 0:
                raise RuntimeError("vermagic= not found in .modinfo")
            end = modinfo.find(b"\x00", pos)
            old_val = modinfo[pos + len(key):end].decode("utf-8")
            new_bytes = (key + new_vermagic.encode("utf-8"))
            slot_len = end - pos
            if len(new_bytes) > slot_len:
                raise RuntimeError(
                    f"New vermagic '{new_vermagic}' ({len(new_bytes)}B) exceeds .modinfo slot ({slot_len}B; old '{old_val}')"
                )
            padded = new_bytes + b"\x00" * (slot_len - len(new_bytes))
            data[sec_off + pos:sec_off + pos + slot_len] = padded
            print(f"[sync_ko] vermagic: '{old_val}' -> '{new_vermagic}'")

    if not found_versions or not found_modinfo:
        raise RuntimeError("Missing __versions or .modinfo ELF section")

    os.makedirs(os.path.dirname(os.path.abspath(ko_out)), exist_ok=True)
    with open(ko_out, "wb") as f:
        f.write(data)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ko-in", required=True)
    ap.add_argument("--ko-out", required=True)
    ap.add_argument("--kbuild-out", required=True)
    ap.add_argument("--sign-file", default="")
    args = ap.parse_args()

    syms = parse_symvers(os.path.join(args.kbuild_out, "Module.symvers"))
    uts = parse_utsrelease(os.path.join(args.kbuild_out, "include/generated/utsrelease.h"))
    vermagic = f"{uts} SMP preempt mod_unload modversions aarch64"

    patch_elf_ko(args.ko_in, args.ko_out, syms, vermagic)

    key_pem = os.path.join(args.kbuild_out, "certs/signing_key.pem")
    key_x509 = os.path.join(args.kbuild_out, "certs/signing_key.x509")
    sign_bin = args.sign_file or os.path.join(args.kbuild_out, "scripts/sign-file")
    if os.path.isfile(sign_bin) and os.path.isfile(key_pem) and os.path.isfile(key_x509):
        subprocess.check_call([sign_bin, "sha512", key_pem, key_x509, args.ko_out])
        print(f"[sync_ko] Signed {args.ko_out} with {key_x509}")


if __name__ == "__main__":
    main()

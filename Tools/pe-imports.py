#!/usr/bin/env python3
"""Dump the import table of a 32-bit PE binary, with each function's IAT address.

Written for the ssstars.scr teardown (see TEARDOWN.md sections 3 and 9).
llvm-objdump --private-headers prints the directory offsets but not the table
itself, so this walks it directly.

The IAT address of each import is the useful output: calls compile to an
indirect call through that address, so grepping a disassembly for it finds
every call site of that function.

    python3 Tools/pe-imports.py bin/ssstars.scr
    ...
    01001018 GetClipBox
    0100101c PatBlt        <- then: grep '100101c' dis.txt
"""
import struct
import sys


def sections(data, pe, opt, opt_size):
    """(virtual_address, virtual_size, raw_pointer, raw_size) per section."""
    count = struct.unpack_from("<H", data, pe + 6)[0]
    base = opt + opt_size
    out = []
    for i in range(count):
        off = base + 40 * i
        vsz, va, rsz, ptr = struct.unpack_from("<IIII", data, off + 8)
        out.append((va, vsz, ptr, rsz))
    return out


def main(path):
    data = open(path, "rb").read()
    pe = struct.unpack_from("<I", data, 0x3C)[0]
    if data[pe:pe + 4] != b"PE\0\0":
        sys.exit("not a PE file")
    opt_size = struct.unpack_from("<H", data, pe + 20)[0]
    opt = pe + 24
    secs = sections(data, pe, opt, opt_size)
    image_base = struct.unpack_from("<I", data, opt + 28)[0]

    def offset(rva):
        """Relative virtual address -> file offset."""
        for va, vsz, ptr, rsz in secs:
            if va <= rva < va + max(vsz, rsz):
                return ptr + (rva - va)
        return None

    def cstring(rva):
        return data[offset(rva):].split(b"\0")[0].decode("ascii", "replace")

    # Data directory entry 1 is the import directory.
    imports_rva = struct.unpack_from("<I", data, opt + 96 + 8)[0]
    cursor = offset(imports_rva)
    total = 0

    while True:
        olt, _stamp, _fwd, name_rva, iat_rva = struct.unpack_from("<IIIII", data, cursor)
        if name_rva == 0:
            break
        print(f"\n--- {cstring(name_rva)} ---")
        # Prefer the original lookup table; it survives binding, the IAT may not.
        thunk = offset(olt if olt else iat_rva)
        iat = iat_rva
        while True:
            entry = struct.unpack_from("<I", data, thunk)[0]
            if entry == 0:
                break
            if entry & 0x80000000:          # imported by ordinal, not name
                label = f"#{entry & 0xFFFF}"
            else:                            # 2-byte hint, then the name
                label = cstring(entry + 2)
            print(f"  {image_base + iat:08x} {label}")
            thunk += 4
            iat += 4
            total += 1
        cursor += 20

    print(f"\n{total} imports")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(sys.argv[1])

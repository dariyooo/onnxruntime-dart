#!/usr/bin/env python3
"""Rewrites an ELF RPATH to $ORIGIN, in place.

Wheels are laid out for Python: auditwheel moves shared dependencies into a
sibling directory and points each library at `$ORIGIN/../<project>.libs`. We
publish one flat directory per target instead, and a bundle step that copies
code assets is free to flatten it further, so that relative hop has to go.

The rewrite only ever shortens. An RPATH is an offset into .dynstr, and a
string there ends at its first NUL, so writing `$ORIGIN\\0` over the front of a
longer string retitles it without moving anything. Nothing else in the file
refers to the tail, which is why this needs no section resizing and no
patchelf on the runner.
"""

from __future__ import annotations

import struct
import sys
import pathlib

RPATH, RUNPATH = 15, 29
TARGET = b"$ORIGIN"


def _dynstr_and_entries(blob: bytes):
    """Offset of .dynstr, and every (file offset, tag, value) in .dynamic."""
    if blob[:4] != b"\x7fELF" or blob[4] != 2 or blob[5] != 1:
        raise ValueError("not a little-endian 64-bit ELF")
    shoff = struct.unpack_from("<Q", blob, 0x28)[0]
    shentsize, shnum, shstrndx = struct.unpack_from("<HHH", blob, 0x3A)

    sections = []
    for i in range(shnum):
        base = shoff + i * shentsize
        name_off = struct.unpack_from("<I", blob, base)[0]
        off, size, link = struct.unpack_from("<QQI", blob, base + 0x18)
        sections.append((name_off, off, size, link))

    shstr = sections[shstrndx][1]

    def name(offset: int) -> str:
        return blob[shstr + offset : blob.index(b"\0", shstr + offset)].decode()

    for name_off, off, size, link in sections:
        if name(name_off) == ".dynamic":
            entries = []
            for j in range(size // 16):
                at = off + j * 16
                tag, value = struct.unpack_from("<qQ", blob, at)
                entries.append((at, tag, value))
                if tag == 0:
                    break
            return sections[link][1], entries
    raise ValueError("no .dynamic section")


def flatten(path: pathlib.Path) -> str | None:
    """Points [path]'s RPATH at its own directory. Returns what it was, or
    None if there was nothing to do: nothing this can rewrite, no RPATH, or an
    RPATH that already only looks beside itself.

    Plenty of files reach here that are not host ELF. A PE arrives whenever a
    provider ships more than one platform. So do Hexagon DSP skeletons, which
    are 32-bit ELF, are loaded onto the NPU rather than by the host loader, and
    travel inside the Windows wheel precisely because they are not for it."""
    blob = bytearray(path.read_bytes())
    if blob[:4] != b"\x7fELF" or blob[4] != 2 or blob[5] != 1:
        return None
    dynstr, entries = _dynstr_and_entries(bytes(blob))

    for _at, tag, value in entries:
        if tag not in (RPATH, RUNPATH):
            continue
        start = dynstr + value
        was = bytes(blob[start : blob.index(b"\0", start)])
        if was == TARGET:
            return None
        if len(was) < len(TARGET):
            raise ValueError(f"{path.name}: RPATH {was!r} is too short to rewrite")
        blob[start : start + len(TARGET) + 1] = TARGET + b"\0"
        path.write_bytes(blob)
        return was.decode()
    return None


def main() -> None:
    for name in sys.argv[1:]:
        path = pathlib.Path(name)
        was = flatten(path)
        print(f"  {path.name}: {was} -> $ORIGIN" if was else f"  {path.name}: unchanged")


if __name__ == "__main__":
    main()

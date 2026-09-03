#!/usr/bin/env python3
"""What architecture a binary is actually built for, read from its header.

Written because a file's path is not evidence of its contents. The DirectX
Shader Compiler ships ARM64EC binaries under `bin/arm64`, which a native ARM64
process cannot load, and the only symptom is `LoadLibrary` failing with error
87 deep inside a graphics driver. A cross-compiled artifact that came out for
the wrong target would fail the same way, in a user's application rather than
in CI, for the targets we publish but have no hardware to load-test on.

So each archive is checked against the target it claims before it is published.
"""

from __future__ import annotations

import pathlib
import struct

# Canonical token -> what each object format calls it.
ELF = {0x03: "x86", 0x28: "arm", 0x3E: "x64", 0xB7: "arm64"}
MACHO = {7: "x86", 0x01000007: "x64", 12: "arm", 0x0100000C: "arm64"}
PE = {0x14C: "x86", 0x1C4: "arm", 0x8664: "x64", 0xAA64: "arm64"}

# What the build matrix calls it -> the canonical token.
TARGETS = {
    "x86_64": "x64",
    "x64": "x64",
    "x86": "x86",
    "x86_64-v8a": "x64",
    "arm64": "arm64",
    "aarch64": "arm64",
    "arm64-v8a": "arm64",
    "armeabi-v7a": "arm",
}


def architectures(path: pathlib.Path) -> set[str]:
    """Every architecture this binary carries, empty if it is not one we read.

    A set rather than one value because Mach-O files can be universal, and
    reporting only the first slice would call a binary wrong for a target it
    actually contains.
    """
    with path.open("rb") as handle:
        head = handle.read(4096)
    if len(head) < 64:
        return set()

    def one(value: str | None) -> set[str]:
        return {value} if value else set()

    if head[:4] == b"\x7fELF":
        return one(ELF.get(struct.unpack_from("<H", head, 0x12)[0]))

    # Little-endian only: nothing we build targets a big-endian Apple platform.
    magic = struct.unpack_from("<I", head, 0)[0]
    if magic in (0xFEEDFACE, 0xFEEDFACF):
        return one(MACHO.get(struct.unpack_from("<I", head, 4)[0]))
    if magic in (0xBEBAFECA, 0xCAFEBABE):  # universal, either byte order
        count = struct.unpack_from(">I", head, 4)[0]
        found = set()
        for i in range(min(count, 32)):
            entry = 8 + i * 20
            if entry + 4 > len(head):
                break
            found |= one(MACHO.get(struct.unpack_from(">I", head, entry)[0]))
        return found

    if head[:2] == b"MZ":
        offset = struct.unpack_from("<I", head, 0x3C)[0]
        if offset + 6 > len(head) or head[offset : offset + 4] != b"PE\0\0":
            return set()
        # ARM64EC and ARM64X both claim AMD64 here and are told apart by the
        # load config, which is past what was read. Neither is something we
        # build, so a Windows ARM64 artifact reporting x64 is wrong however it
        # came to be, and the caller reports it as such.
        return one(PE.get(struct.unpack_from("<H", head, offset + 4)[0]))

    return set()  # wasm, or a static library, or something else entirely


def verify(path: pathlib.Path, arch: str) -> None:
    """Raises if [path] is a binary built for something other than [arch]."""
    want = TARGETS.get(arch)
    if want is None:
        raise SystemExit(f"no architecture known for the target {arch!r}")

    found = architectures(path)
    if not found:
        return  # Not an object file we read, so nothing to contradict.
    if want not in found:
        raise SystemExit(
            f"{path.name} is built for {', '.join(sorted(found))}, but this "
            f"artifact is for {arch}. Publishing it would fail to load on the "
            f"target it names, which is a build configuration problem, not a "
            f"packaging one."
        )

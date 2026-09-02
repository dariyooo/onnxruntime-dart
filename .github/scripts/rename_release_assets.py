#!/usr/bin/env python3
"""Renames staged archives to the names the build hook installs from.

One rule everywhere: the component comes first, then the target.
`base-linux-x64.tar.gz`, `full-linux-x64.tar.gz`, `webgpu-linux-x64.tar.gz`,
`extensions-linux-x64.tar.gz`. What arrives here is named however the job that
built it happened to name it, which is not the same shape:

  * the runtime is named for the target alone, with the variant appended,
    because its configuration ids are `linux-x64` and `linux-x64-full`
  * a provider built through the runtime pipeline is `linux-x64-webgpu`, for
    the same reason
  * a mirrored provider is already `qnn-linux-x64`

The hook derives one name, so the publisher has to produce that one. The
checksum sidecar names the file inside it, but the hook reads only the hash, so
renaming both is enough.

    rename_release_assets.py dist/runtime runtime
    rename_release_assets.py dist/ep-webgpu webgpu
"""

from __future__ import annotations

import pathlib
import sys

SIDECAR = ".sha256"


def renamed(name: str, component: str) -> str | None:
    """The published name for [name], or None to leave it alone."""
    if component == "runtime":
        # Headers are not per-target and are asked for by that name.
        if name == "headers.tar.gz":
            return None
        target = name[: -len(".tar.gz")]
        if target.endswith("-full"):
            return f"full-{target[: -len('-full')]}.tar.gz"
        return f"base-{target}.tar.gz"

    target = name[: -len(".tar.gz")]
    if target.endswith(f"-{component}"):
        return f"{component}-{target[: -len(f'-{component}')]}.tar.gz"
    return None


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit("usage: rename_release_assets.py <directory> <component>")

    directory = pathlib.Path(sys.argv[1])
    component = sys.argv[2].removeprefix("ep-")

    for path in sorted(directory.iterdir()):
        name, suffix = path.name, ""
        if name.endswith(SIDECAR):
            name, suffix = name[: -len(SIDECAR)], SIDECAR
        if not name.endswith(".tar.gz"):
            continue

        wanted = renamed(name, component)
        if wanted is None or wanted == name:
            continue

        destination = directory / (wanted + suffix)
        print(f"  {path.name} -> {destination.name}")
        path.rename(destination)


if __name__ == "__main__":
    main()

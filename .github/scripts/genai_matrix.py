#!/usr/bin/env python3
"""What ONNX Runtime GenAI publishes, and what we mirror it as.

Nothing is compiled here. Upstream builds and publishes the library for every
target it supports, so this describes their archives and the names ours take,
in the same shape as ep_matrix does for the plugins.

The target list is upstream's rather than ours, and it is shorter: there is no
macOS x64 archive and no WebAssembly one at all. A target we support and they
do not is a gap the hook has to name, not one to paper over.
"""

from __future__ import annotations

import os
import pathlib
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]

COMPONENT = "genai"

#: The upstream repository the archives come from.
UPSTREAM = "microsoft/onnxruntime-genai"

#: Our target id -> the fragment upstream names its archive with.
#:
#: Android and iOS are absent on purpose. Upstream ships those as an `.aar` and
#: a framework zip, which are a different shape from the plain library archives
#: and need their own unpacking. They are worth adding, and adding them means
#: writing that, not extending this table.
TARGETS: dict[str, str] = {
    "linux-x64": "linux-x64",
    "linux-arm64": "linux-arm64",
    "macos-arm64": "osx-arm64",
    "windows-x64": "win-x64",
    "windows-arm64": "win-arm64",
}

#: The library inside each archive, by the platform the target names.
LIBRARY = {
    "linux": "libonnxruntime-genai.so",
    "macos": "libonnxruntime-genai.dylib",
    "windows": "onnxruntime-genai.dll",
}


def version() -> str:
    """The version upstream calls this, from the pinned tree.

    VERSION_INFO rather than a tag: the file is what the build reads, and it is
    what the release archives are named for.
    """
    return (
        (REPO_ROOT / "third_party" / "onnxruntime-genai" / "VERSION_INFO")
        .read_text(encoding="utf-8")
        .strip()
    )


def release_tag() -> str:
    """The tag our release is published under."""
    return f"{COMPONENT}-v{version()}"


def upstream_tag() -> str:
    """The tag upstream published the archives under."""
    return f"v{version()}"


def upstream_asset(target: str) -> str:
    """The archive upstream publishes for [target]."""
    fragment = TARGETS[target]
    suffix = "zip" if target.startswith("windows-") else "tar.gz"
    return f"onnxruntime-genai-{version()}-{fragment}.{suffix}"


def our_asset(target: str) -> str:
    """The archive we publish for [target], named as the hook asks for it."""
    return f"{COMPONENT}-{target}.tar.gz"


def library_for(target: str) -> str:
    """The library file inside the archive for [target]."""
    for platform, name in LIBRARY.items():
        if target.startswith(platform):
            return name
    raise SystemExit(f"no library name known for {target}")


def targets() -> list[str]:
    return list(TARGETS)


if __name__ == "__main__":
    print(f"{COMPONENT} {version()} from {UPSTREAM} {upstream_tag()}")
    for target in targets():
        print(f"  {target:16} {upstream_asset(target):48} -> {our_asset(target)}")

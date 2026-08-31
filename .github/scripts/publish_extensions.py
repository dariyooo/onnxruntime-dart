#!/usr/bin/env python3
"""Publishes the onnxruntime-extensions release, or refreshes it.

Its own stream, like each provider: extensions versions itself separately from
the runtime and works against a range of them, so tying it to a runtime release
would republish binaries that had not changed.

Created once and refreshed after that, so a build that went wrong replaces its
assets rather than leaving a trail of tags differing only in which was good.
"""

from __future__ import annotations

import os
import pathlib
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import extensions_matrix  # noqa: E402

REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]


def release_exists(tag: str) -> bool:
    return subprocess.run(
        ("gh", "release", "view", tag), capture_output=True
    ).returncode == 0


def main() -> None:
    tag = extensions_matrix.release_tag()
    staged = REPO_ROOT / "dist" / extensions_matrix.COMPONENT
    assets = sorted(staged.glob("*"))
    if not assets:
        raise SystemExit(f"nothing staged in {staged}")

    notes = (
        f"onnxruntime-extensions {extensions_matrix.version()}, built from the "
        f"pinned submodule.\n\n"
        f"Custom operators ONNX Runtime does not have: tokenizers, text, image "
        f"and audio preprocessing that run inside the graph. Loaded through "
        f"RegisterCustomOpsLibrary_V2 and installed by the "
        f"onnxruntime_extensions package. Each archive is verified against the "
        f"SHA-256 in its sidecar."
    )

    if release_exists(tag):
        print(f"refreshing {tag}")
        subprocess.run(
            ("gh", "release", "upload", tag, *map(str, assets), "--clobber"),
            check=True,
        )
        subprocess.run(("gh", "release", "edit", tag, "--notes", notes), check=True)
    else:
        print(f"creating {tag}")
        subprocess.run(
            ("gh", "release", "create", tag, *map(str, assets),
             "--title", tag, "--notes", notes),
            check=True,
        )


if __name__ == "__main__":
    main()

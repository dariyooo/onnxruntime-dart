#!/usr/bin/env python3
"""Publishes the ONNX Runtime GenAI release, or refreshes it.

Its own stream, because GenAI versions separately from the runtime and keeps
working across runtime releases: it resolves `OrtGetApiBase` out of whatever
runtime is loaded rather than linking one. Tying it to a runtime release would
republish binaries that had not changed.

Created once and refreshed after that, so rebuilding one that went wrong
replaces its assets under the same name rather than leaving a trail of tags
differing only in which was any good.
"""

from __future__ import annotations

import os
import pathlib
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import genai_matrix  # noqa: E402

REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]


def release_exists(tag: str) -> bool:
    return (
        subprocess.run(
            ("gh", "release", "view", tag), capture_output=True
        ).returncode
        == 0
    )


def prune(tag: str, keep: set[str]) -> None:
    """Drops assets the release carries that we no longer publish.

    Uploading clobbers by name, so a renaming leaves the old names in place
    looking current while nothing asks for them any more.
    """
    listed = subprocess.run(
        ("gh", "release", "view", tag, "--json", "assets", "--jq", ".assets[].name"),
        capture_output=True,
        text=True,
        check=True,
    ).stdout.split()

    for name in listed:
        if name in keep:
            continue
        print(f"  dropping stale {name}")
        subprocess.run(("gh", "release", "delete-asset", tag, name, "-y"), check=True)


def main() -> None:
    tag = genai_matrix.release_tag()
    staged = REPO_ROOT / "dist" / genai_matrix.COMPONENT

    assets = sorted(staged.glob("*"))
    if not assets:
        raise SystemExit(f"nothing staged in {staged}")

    notes = (
        f"ONNX Runtime GenAI {genai_matrix.version()}, mirrored from "
        f"{genai_matrix.UPSTREAM} {genai_matrix.upstream_tag()}.\n\n"
        f"Token generation, KV caching and sampling on top of ONNX Runtime. "
        f"The library resolves `OrtGetApiBase` in a runtime that is already "
        f"loaded rather than linking one, so a runtime has to be installed "
        f"beside it. Installed by the onnxruntime_genai_binaries package; each "
        f"archive is verified against the SHA-256 in its sidecar.\n\n"
        f"Published for {', '.join(genai_matrix.targets())}. Upstream has no "
        f"macOS x64 or WebAssembly build."
    )

    if release_exists(tag):
        print(f"refreshing {tag}")
        subprocess.run(
            ("gh", "release", "upload", tag, *map(str, assets), "--clobber"),
            check=True,
        )
        prune(tag, {a.name for a in assets})
        subprocess.run(("gh", "release", "edit", tag, "--notes", notes), check=True)
    else:
        print(f"creating {tag}")
        subprocess.run(
            (
                "gh", "release", "create", tag, *map(str, assets),
                "--title", tag, "--notes", notes,
            ),
            check=True,
        )


if __name__ == "__main__":
    main()

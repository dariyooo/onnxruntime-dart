#!/usr/bin/env python3
"""Publishes one execution provider's release, or refreshes it.

Each provider is its own stream: ONNX Runtime versions its plugins separately
from the runtime and from each other, and a plugin keeps working past the
runtime it shipped beside. Tying them to a runtime release would republish
binaries that had not changed.

Created once and refreshed after that, so rebuilding one that went wrong
replaces its assets under the same name rather than leaving a trail of tags
differing only in which was any good.
"""

from __future__ import annotations

import argparse
import os
import pathlib
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import ep_matrix  # noqa: E402

REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]


def release_exists(tag: str) -> bool:
    return (
        subprocess.run(
            ("gh", "release", "view", tag),
            capture_output=True,
        ).returncode
        == 0
    )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("provider")
    args = parser.parse_args()

    provider = ep_matrix.by_name(args.provider)
    tag = provider.release_tag
    staged = REPO_ROOT / "dist" / f"ep-{provider.name}"

    assets = sorted(staged.glob("*"))
    if not assets:
        raise SystemExit(f"nothing staged in {staged}")

    source = (
        f"mirrored from onnxruntime {provider.upstream_tag}"
        if provider.source == ep_matrix.FETCH
        else "built from the pinned submodule"
    )
    notes = (
        f"The {provider.name} execution provider, version {provider.version}, "
        f"{source}.\n\n"
        f"Works with ONNX Runtime {provider.minimum_runtime} and newer, so it "
        f"does not move when the runtime does. Installed by the "
        f"onnxruntime_ep_{provider.name} package; each archive is verified "
        f"against the SHA-256 in its sidecar."
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
            (
                "gh", "release", "create", tag, *map(str, assets),
                "--title", tag, "--notes", notes,
            ),
            check=True,
        )


if __name__ == "__main__":
    main()

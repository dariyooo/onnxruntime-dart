#!/usr/bin/env python3
"""Names the release for whatever ONNX Runtime commit is checked out.

The submodule pin is the source of truth. Moving it is what produces a new
release, so the name is derived from it rather than from a tag someone
remembers to push.

Two cases:

  * the pin sits exactly on an upstream tag, which is the normal one. The
    release is named for that version and is a real release.
  * the pin is somewhere else, because we are trying a fix that is not in a
    release yet. The name carries the commit so it cannot be mistaken for a
    version, and the release is marked prerelease.
"""

from __future__ import annotations

import argparse
import os
import pathlib
import re
import subprocess

REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
SUBMODULE = REPO_ROOT / "third_party" / "onnxruntime"

# Upstream tags are v1.29.0. Anything else is not a version we can name.
_VERSION_TAG = re.compile(r"^v(\d+\.\d+\.\d+)$")


def _git(checkout: pathlib.Path, *args: str) -> str | None:
    try:
        out = subprocess.run(
            ("git", "-C", str(checkout), *args),
            capture_output=True,
            text=True,
            check=True,
        )
    except (subprocess.CalledProcessError, FileNotFoundError):
        return None
    return out.stdout.strip() or None


def identity(checkout: pathlib.Path = SUBMODULE) -> tuple[str, bool]:
    """The version part of the release name, and whether the ONNX Runtime it
    was built from is unreleased."""
    exact = _git(checkout, "describe", "--tags", "--exact-match", "HEAD")
    if exact and _VERSION_TAG.match(exact):
        return exact, False

    # Not on a tag. Name it for the version in the tree plus the commit, so it
    # sorts beside its neighbours and still says exactly which build it is.
    version = (checkout / "VERSION_NUMBER").read_text(encoding="utf-8").strip()
    commit = _git(checkout, "rev-parse", "--short=12", "HEAD") or "unknown"
    return f"v{version}-g{commit}", True


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--component",
        default="runtime",
        help="release stream: runtime, ep-webgpu, ep-qnn",
    )
    args = parser.parse_args()

    version, prerelease = identity()
    tag = f"{args.component}-{version}"

    print(f"tag={tag}")
    print(f"version={version}")
    print(f"prerelease={'true' if prerelease else 'false'}")

    if output := os.environ.get("GITHUB_OUTPUT"):
        with open(output, "a", encoding="utf-8") as handle:
            handle.write(f"tag={tag}\n")
            handle.write(f"version={version}\n")
            handle.write(f"prerelease={'true' if prerelease else 'false'}\n")


if __name__ == "__main__":
    main()

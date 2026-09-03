#!/usr/bin/env python3
"""Stages the GenAI library and points its build hook at it.

Separate from locate_library.py because it stages a different component from a
different release, and because GenAI is published for fewer targets than the
runtime is: a target upstream has no build for is not an error here, it is a
job that runs the tests it can and says which it could not.

    locate_genai.py <target-id>
"""

from __future__ import annotations

import os
import pathlib
import subprocess
import sys
import tarfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import genai_matrix  # noqa: E402
import locate_library  # noqa: E402

REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("usage: locate_genai.py <target-id>")

    target = sys.argv[1]
    if target not in genai_matrix.TARGETS:
        # Not a failure. Upstream publishes no macOS x64 or WebAssembly build,
        # and a job on one of those should say so and carry on rather than
        # fail for a library that was never going to exist.
        print(f"::notice::no GenAI build for {target}; its tests will skip")
        return

    staged = REPO_ROOT / ".local" / "genai" / target
    staged.mkdir(parents=True, exist_ok=True)

    archive = REPO_ROOT / ".local" / "artifacts" / "genai" / (
        genai_matrix.our_asset(target)
    )
    if not archive.is_file():
        # Not built in this run, so take it from the release the pinned
        # submodule names.
        archive = staged / genai_matrix.our_asset(target)
        subprocess.run(
            (
                "gh", "release", "download", genai_matrix.release_tag(),
                "--pattern", genai_matrix.our_asset(target),
                "--dir", str(staged), "--clobber",
            ),
            check=True,
        )

    with tarfile.open(archive) as tar:
        tar.extractall(staged)

    library = staged / genai_matrix.library_for(target)
    if not library.is_file():
        raise SystemExit(f"{archive} held no {library.name}")

    locate_library.point_hook_at(staged, "onnxruntime_genai_binaries")
    locate_library.export("ONNXRUNTIME_GENAI_LIB", library)


if __name__ == "__main__":
    main()

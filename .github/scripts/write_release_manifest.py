#!/usr/bin/env python3
"""Generates the release manifest the build hook reads.

Pins the release tag and the SHA-256 of every asset, so a hook can only ever
install bytes this release produced. Run after the archives exist and before the
package is published.
"""

from __future__ import annotations

import os
import pathlib
import sys

REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
DIST = REPO_ROOT / "dist" / "runtime"
MANIFEST = (
    REPO_ROOT / "packages" / "onnxruntime_dart" / "lib" / "src" / "hook" / "release.g.dart"
)


def main() -> None:
    tag = os.environ.get("RELEASE_TAG")
    if not tag:
        raise SystemExit("RELEASE_TAG is unset")

    digests: dict[str, str] = {}
    for sidecar in sorted(DIST.glob("*.tar.gz.sha256")):
        target = sidecar.name.removesuffix(".tar.gz.sha256")
        if target == "headers":
            continue
        digests[target] = sidecar.read_text(encoding="utf-8").split()[0]

    if not digests:
        raise SystemExit(f"no archives found under {DIST}")

    entries = "\n".join(f"  '{t}': '{d}'," for t, d in sorted(digests.items()))
    MANIFEST.write_text(
        "// AUTO GENERATED FILE, DO NOT EDIT.\n"
        "//\n"
        "// Written by .github/scripts/write_release_manifest.py during a\n"
        "// release. It pins the exact assets the build hook may install.\n"
        "\n"
        "/// Release the prebuilt libraries are fetched from.\n"
        f"const releaseTag = '{tag}';\n"
        "\n"
        "/// SHA-256 of each release asset, keyed by target identifier.\n"
        "const assetSha256 = <String, String>{\n"
        f"{entries}\n"
        "};\n",
        encoding="utf-8",
    )
    print(f"pinned {len(digests)} assets to {tag}")


if __name__ == "__main__":
    main()

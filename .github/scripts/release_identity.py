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
import sys
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
    """The version part of the release name, and whether the source was tagged.

    The name is the version and nothing else. It used to carry the commit when
    the submodule was not sitting on a tag, which read well and could never be
    installed: the build hook derives the tag it asks for from a package
    version, so a name with a commit in it is one nothing looks for. The commit
    is in the release notes instead, where it informs without being load
    bearing.

    Whether the commit is exactly a tag only sets the prerelease flag, so it is
    allowed to be unknown. A shallow checkout has no tags, and answering "not
    tagged" there is wrong but harmless.
    """
    version = (checkout / "VERSION_NUMBER").read_text(encoding="utf-8").strip()

    exact = _git(checkout, "describe", "--tags", "--exact-match", "HEAD")
    tagged = bool(exact and _VERSION_TAG.match(exact))
    return f"v{version}", not tagged


def provider_version(component: str) -> str | None:
    """The plugin's own version, for a component that has one.

    A provider is versioned by ONNX Runtime separately from the runtime and
    keeps working across runtime releases, so naming its release after the
    runtime would be wrong twice: it would republish an unchanged binary
    whenever the runtime moved, and it would not be the version the package
    asks for. The build hook derives the tag from the package version, so the
    two have to agree or nothing installs.

    Asked of ep_matrix rather than read from the submodule, because not every
    provider is built from it. QNN is mirrored from a wheel and has no
    plugin-ep directory, and reading one would silently fall back to the
    runtime version, which is the exact mistake this exists to prevent.
    """
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

    if component == "extensions":
        # Versioned separately from the runtime, and published by
        # publish_extensions.py from this same number. Asked here too so there
        # is one answer to what a component's release is called.
        import extensions_matrix  # noqa: PLC0415

        return extensions_matrix.version()

    name = component.removeprefix("ep-")
    if name == component:
        return None

    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import ep_matrix  # noqa: PLC0415

    try:
        return ep_matrix.by_name(name).version
    except SystemExit:
        return None


def release_identity_for(component: str) -> tuple[str, str, bool]:
    """The tag, version and prerelease flag for one release stream.

    One function rather than a calculation repeated per caller, because the
    name it produces has to match what the build hook asks for, and the last
    time there were two of these they disagreed.
    """
    version, prerelease = identity()
    if (plugin := provider_version(component)) is not None:
        version, prerelease = f"v{plugin}", False
    return f"{component}-{version}", version, prerelease


def release_tag(component: str = "runtime") -> str:
    """The tag alone, for callers that only need to find the release."""
    return release_identity_for(component)[0]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--component",
        default="runtime",
        help="release stream: runtime, ep-webgpu, ep-qnn",
    )
    args = parser.parse_args()

    tag, version, prerelease = release_identity_for(args.component)

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

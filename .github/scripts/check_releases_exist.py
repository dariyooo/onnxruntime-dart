#!/usr/bin/env python3
"""Checks that every component this checkout declares has a release.

Each package installs from a release named after its own version, so a version
that has no release is a package that cannot be installed. Nothing notices
until someone tries, and then the failure is a 404 from a build hook rather
than anything that names the cause.

Only meaningful when testing what is published. On a run that builds, the
release for a version just bumped does not exist yet and is about to be
created by that very run.

    check_releases_exist.py
"""

import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import ep_matrix  # noqa: E402
import release_identity  # noqa: E402


def exists(tag: str) -> bool:
    return (
        subprocess.run(
            ("gh", "release", "view", tag), capture_output=True
        ).returncode
        == 0
    )


def main() -> None:
    components = ["runtime", "extensions"]
    components += [f"ep-{provider.name}" for provider in ep_matrix.PROVIDERS]

    missing = []
    for component in components:
        tag = release_identity.release_tag(component)
        if exists(tag):
            print(f"  {component}: {tag}")
        else:
            print(f"  {component}: {tag} MISSING")
            missing.append((component, tag))

    if missing:
        print()
        for component, tag in missing:
            print(
                f"::error::{component} declares a version whose release does "
                f"not exist: {tag}. Anything depending on it cannot install."
            )
        raise SystemExit(1)


if __name__ == "__main__":
    main()

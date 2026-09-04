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
import genai_matrix  # noqa: E402
import ort_matrix  # noqa: E402
import release_identity  # noqa: E402
import rename_release_assets  # noqa: E402


def exists(tag: str) -> bool:
    return (
        subprocess.run(
            ("gh", "release", "view", tag), capture_output=True
        ).returncode
        == 0
    )


def ever_published(prefix: str) -> bool:
    """Whether any release of [prefix] exists, at any version.

    A component that has never shipped is not the same as one whose declared
    version has outrun its release. The first is a component waiting to be
    tagged, which is a decision rather than a fault; the second is a package
    somebody cannot install.
    """
    listed = subprocess.run(
        ("gh", "release", "list", "--limit", "100", "--json", "tagName",
         "--jq", ".[].tagName"),
        capture_output=True,
        text=True,
    ).stdout.split()
    return any(tag.startswith(f"{prefix}-v") for tag in listed)


def published(tag: str) -> set[str]:
    """Every asset name the release carries."""
    result = subprocess.run(
        ("gh", "release", "view", tag, "--json", "assets", "-q", ".assets[].name"),
        capture_output=True,
        text=True,
    )
    return set(result.stdout.split())


def runtime_holes(tag: str) -> list[str]:
    """The runtime archives the matrix builds that the release does not carry.

    A release that exists is not the same as a release that is complete. One
    configuration failing to publish leaves a hole that nothing notices until
    a hook asks for that target and gets a 404, which is at install time on
    somebody else's machine.

    Named through the same rule the publisher uses, so this cannot drift from
    what is actually uploaded.
    """
    have = published(tag)
    missing = []
    for config in ort_matrix.CONFIGURATIONS:
        for local in (config.id, f"{config.id}-full"):
            wanted = rename_release_assets.renamed(f"{local}.tar.gz", "runtime")
            if wanted not in have:
                missing.append(wanted)
    return missing


def main() -> None:
    components = ["runtime", "extensions", genai_matrix.COMPONENT]
    components += [f"ep-{provider.name}" for provider in ep_matrix.PROVIDERS]

    missing = []
    for component in components:
        # GenAI versions from its own submodule, so its tag comes from there.
        # release_identity knows the runtime and the providers, and falling
        # through to it named genai after the runtime version.
        tag = (
            genai_matrix.release_tag()
            if component == genai_matrix.COMPONENT
            else release_identity.release_tag(component)
        )
        if exists(tag):
            holes = runtime_holes(tag) if component == "runtime" else []
            if holes:
                print(f"  {component}: {tag} INCOMPLETE ({len(holes)} missing)")
                for name in holes:
                    print(f"::error::{tag} does not carry {name}")
                raise SystemExit(1)
            print(f"  {component}: {tag}")
        elif not ever_published(component):
            # Never tagged. Publishing is deliberately a separate decision from
            # building, so a component waiting for one is not a failure.
            print(f"  {component}: {tag} not published yet")
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

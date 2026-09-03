#!/usr/bin/env python3
"""Downloads published binaries into the layout the test jobs expect.

The build jobs hand their output to the test jobs as run artifacts, which only
exist while the run does. This fetches the same things from the releases
instead, so the suite can be run against what is actually published without
rebuilding anything. `locate_library.py` reads what this writes, unchanged.

Asset names are not consistent between providers, because a built provider is
named after the configuration it was built for and a mirrored one is named
after itself. Both spellings are tried rather than encoded per provider, so a
new provider needs nothing here.

    fetch_release_binaries.py linux-x64
"""

import argparse
import os
import pathlib
import subprocess
import sys

REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
ARTIFACTS = REPO_ROOT / ".local" / "artifacts"
EXTENSIONS = REPO_ROOT / ".local" / "extensions"

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ep_matrix  # noqa: E402
import release_identity  # noqa: E402


def download(tag: str, asset: str, into: pathlib.Path) -> bool:
    """Fetches one asset, returning whether it was there."""
    into.mkdir(parents=True, exist_ok=True)
    result = subprocess.run(
        ["gh", "release", "download", tag, "--pattern", asset, "--dir", str(into),
         "--clobber"],
        capture_output=True,
        text=True,
    )
    if result.returncode == 0:
        return True
    print(f"  {tag}: no {asset} ({result.stderr.strip().splitlines()[-1:]})")
    return False


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("config", help="configuration id, e.g. linux-x64")
    parser.add_argument("--runtime-tag", default=None)
    args = parser.parse_args()

    config = args.config
    runtime_tag = args.runtime_tag or release_identity.release_tag("runtime")

    print(f"runtime: {runtime_tag}")
    # Published component first, staged the way the build jobs hand it over,
    # because locate_library.py reads the staged layout either way.
    variant = "full" if config.endswith("-full") else "base"
    published = f"{variant}-{config.removesuffix('-full')}.tar.gz"
    into = ARTIFACTS / "runtime"
    if not download(runtime_tag, published, into):
        raise SystemExit(f"{runtime_tag} has no {published}")
    (into / published).rename(into / f"{config}.tar.gz")

    for provider in ep_matrix.PROVIDERS:
        if config not in provider.targets:
            print(f"  {provider.name}: not published for {config}")
            continue

        into = ARTIFACTS / f"ep-{provider.name}"
        # Built providers are named for the configuration, mirrored ones for
        # themselves, and cuda adds its toolkit. Whichever lands is renamed to
        # the one name locate_library.py looks for.
        wanted = into / f"{config}-{provider.name}.tar.gz"
        for pattern in (
            f"{config}-{provider.name}.tar.gz",
            f"{provider.name}-*{config}.tar.gz",
        ):
            if download(provider.release_tag, pattern, into):
                # The newest, not the first one the glob happens to yield. CUDA
                # publishes an archive per toolkit, so a target has both
                # cuda-cuda12-<target> and cuda-cuda13-<target>, and taking
                # either arbitrarily gives a plugin whose runtime is not the
                # one CI installed. Sorting puts the newer toolkit last.
                archives = sorted(
                    p for p in into.glob("*.tar.gz")
                    if not p.name.endswith(".sha256")
                )
                found = archives[-1] if archives else None
                if found and found != wanted:
                    for stale in archives[:-1]:
                        stale.unlink()
                    found.rename(wanted)
                break
        else:
            raise SystemExit(
                f"{provider.release_tag} is published for {config} but holds "
                f"no archive for it"
            )

    extensions_tag = release_identity.release_tag("extensions")
    print(f"extensions: {extensions_tag}")
    download(extensions_tag, f"extensions-{config}.tar.gz", EXTENSIONS)


if __name__ == "__main__":
    main()

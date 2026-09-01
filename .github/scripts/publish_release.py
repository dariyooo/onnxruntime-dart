#!/usr/bin/env python3
"""Creates a release, or refreshes the one already there.

Every stream publishes the same way, so it is worth having one place that knows
how: create when the tag is new, otherwise replace the assets under the same
tag. Re-running a pipeline on an unchanged checkout must land exactly where the
last run did, with no second tag and no leftovers.

Pruning is the part that is easy to get wrong. Uploading clobbers by name, so a
renamed asset leaves the old name behind looking current while nothing asks for
it any more. That is worse than a missing asset: it reads as a working download
right until someone depends on it.
"""

from __future__ import annotations

import argparse
import pathlib
import subprocess
import sys


def exists(tag: str) -> bool:
    return subprocess.run(
        ("gh", "release", "view", tag), capture_output=True
    ).returncode == 0


def published_assets(tag: str) -> list[str]:
    return subprocess.run(
        ("gh", "release", "view", tag, "--json", "assets", "--jq", ".assets[].name"),
        capture_output=True,
        text=True,
        check=True,
    ).stdout.split()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tag", required=True)
    parser.add_argument("--directory", required=True, type=pathlib.Path)
    parser.add_argument("--notes", required=True)
    parser.add_argument(
        "--prerelease",
        action="store_true",
        help="built from an ONNX Runtime with no release of its own, so it "
        "must not look like one",
    )
    args = parser.parse_args()

    assets = sorted(p for p in args.directory.glob("*") if p.is_file())
    if not assets:
        raise SystemExit(f"nothing to publish in {args.directory}")

    names = {p.name for p in assets}

    if not exists(args.tag):
        print(f"creating {args.tag} with {len(assets)} assets")
        flags = ("--prerelease",) if args.prerelease else ()
        subprocess.run(
            ("gh", "release", "create", args.tag, *map(str, assets),
             "--title", args.tag, "--notes", args.notes, *flags),
            check=True,
        )
        return

    print(f"refreshing {args.tag} with {len(assets)} assets")
    subprocess.run(
        ("gh", "release", "upload", args.tag, *map(str, assets), "--clobber"),
        check=True,
    )
    subprocess.run(
        ("gh", "release", "edit", args.tag, "--notes", args.notes), check=True
    )

    for stale in published_assets(args.tag):
        if stale in names:
            continue
        print(f"  dropping stale {stale}")
        subprocess.run(
            ("gh", "release", "delete-asset", args.tag, stale, "-y"), check=True
        )


if __name__ == "__main__":
    main()

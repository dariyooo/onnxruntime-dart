#!/usr/bin/env python3
"""Emits the build matrix as a GitHub Actions job output."""

from __future__ import annotations

import dataclasses
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import ort_matrix  # noqa: E402


def main() -> None:
    configs = ort_matrix.select(os.environ.get("FILTER", "all"))
    groups = ort_matrix.group(configs)

    include = [
        {
            "group": g.id,
            "platform": g.platform,
            "runner": g.runner,
            "ids": " ".join(c.id for c in g.configs),
        }
        for g in groups
    ]

    print(f"matrix={json.dumps({'include': include}, separators=(',', ':'))}")
    print(f"count={len(configs)}")

    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as handle:
            handle.write(
                f"### Building {len(configs)} configurations in {len(groups)} jobs\n\n"
            )
            handle.write("| job | runner | configurations |\n|---|---|---|\n")
            for g in groups:
                ids = ", ".join(
                    f"`{c.id}`" + (" ⚠️" if c.unproven else "") for c in g.configs
                )
                handle.write(f"| `{g.id}` | `{g.runner}` | {ids} |\n")


if __name__ == "__main__":
    main()

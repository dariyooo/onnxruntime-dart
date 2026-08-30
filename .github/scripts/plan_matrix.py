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

    include = [
        {
            "id": c.id,
            "platform": c.platform,
            "arch": c.arch,
            "runner": c.runner,
        }
        for c in configs
    ]

    print(f"matrix={json.dumps({'include': include}, separators=(',', ':'))}")
    print(f"count={len(include)}")

    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as handle:
            handle.write(f"### Building {len(include)} configurations\n\n")
            handle.write("| id | runner | flags |\n|---|---|---|\n")
            for c in configs:
                note = " ⚠️ unproven" if c.unproven else ""
                handle.write(f"| `{c.id}`{note} | `{c.runner}` | `{' '.join(c.args)}` |\n")


if __name__ == "__main__":
    main()

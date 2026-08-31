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

    # One pipeline per stream. Without this every caller builds everything,
    # which is how a provider ended up gating a runtime.
    stream = os.environ.get("STREAM", "")
    if stream:
        streams = {c.stream for c in ort_matrix.all_configurations()}
        if stream not in streams:
            raise SystemExit(
                f"unknown stream {stream!r}; expected one of "
                f"{', '.join(sorted(streams))}"
            )
        configs = [c for c in configs if c.stream == stream]
        if not configs:
            raise SystemExit(f"no {stream} configuration matches the filter")

    # One job per configuration. They share nothing worth sharing: each needs
    # its own dependency build directory, so a shared job only serialises work
    # that could run in parallel. Runners are free on a public repository.
    include = [
        {
            "id": c.id,
            "platform": c.platform,
            "runner": c.runner,
            "variant": c.variant,
        }
        for c in configs
    ]

    print(f"matrix={json.dumps({'include': include}, separators=(',', ':'))}")
    print(f"count={len(configs)}")

    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as handle:
            handle.write(f"### Building {len(configs)} configurations\n\n")
            handle.write("| configuration | runner | flags |\n|---|---|---|\n")
            for c in configs:
                note = " ⚠️ unproven" if c.unproven else ""
                handle.write(
                    f"| `{c.id}`{note} | `{c.runner}` | `{' '.join(c.args)}` |\n"
                )


if __name__ == "__main__":
    main()

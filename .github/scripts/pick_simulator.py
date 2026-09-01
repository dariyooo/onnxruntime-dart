#!/usr/bin/env python3
"""Prints the UDID of an iPhone simulator to run on.

Discovery is normally quick, but simctl can wedge against a stale
CoreSimulator service and then never return rather than failing. A deadline
turns that into a clear message and one retry, instead of a job that sits
silent until its timeout.
"""

from __future__ import annotations

import json
import subprocess
import sys
import time

DEADLINE = 120


def listing() -> str:
    return subprocess.run(
        ("xcrun", "simctl", "list", "devices", "available", "-j"),
        capture_output=True,
        text=True,
        timeout=DEADLINE,
        check=True,
    ).stdout


def restart_core_simulator() -> None:
    print("simctl did not answer; restarting CoreSimulator", file=sys.stderr)
    subprocess.run(
        ("sudo", "killall", "-9", "com.apple.CoreSimulator.CoreSimulatorService"),
        check=False,
        capture_output=True,
    )
    time.sleep(5)


def main() -> None:
    for attempt in range(2):
        try:
            devices = json.loads(listing())["devices"]
        except subprocess.TimeoutExpired:
            if attempt == 0:
                restart_core_simulator()
                continue
            raise SystemExit(
                f"xcrun simctl list did not answer within {DEADLINE}s twice"
            )

        for runtime, entries in sorted(devices.items()):
            if "iOS" not in runtime:
                continue
            for entry in entries:
                if entry["name"].startswith("iPhone"):
                    print(entry["udid"])
                    return

        raise SystemExit(
            "no iPhone simulator is available; runtimes seen: "
            + ", ".join(sorted(devices))
        )


if __name__ == "__main__":
    main()

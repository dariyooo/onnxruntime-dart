#!/usr/bin/env python3
"""Prints the UDID of an iPhone simulator to run on.

`xcrun simctl list` hangs outright on a cold runner rather than failing, and a
hang there is indistinguishable from a slow boot: it once took a device job to
its 45 minute timeout without printing a line. So the call gets a deadline, and
a hang is treated as a stale CoreSimulator service and retried once.
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

#!/usr/bin/env python3
"""Renames a provider's archives to the name the build hook installs from.

A provider built through the runtime pipeline is built as configurations whose
ids already carry the provider name, so its archives arrive as
`<target>-<provider>.tar.gz`. A mirrored provider is named by its own script and
arrives as `<provider>-<target>.tar.gz`, which is what `providerAssetFileName`
in onnxruntime_hook asks for. The two have to agree or the package cannot
install, so this makes the built ones match the installed name.

    rename_provider_assets.py dist/ep-webgpu webgpu
"""

import pathlib
import sys


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit("usage: rename_provider_assets.py <directory> <provider>")

    directory = pathlib.Path(sys.argv[1])
    provider = sys.argv[2]

    for path in sorted(directory.iterdir()):
        name = path.name
        suffix = ""
        if name.endswith(".sha256"):
            name, suffix = name[: -len(".sha256")], ".sha256"
        if not name.endswith(f"-{provider}.tar.gz"):
            continue

        target = name[: -len(f"-{provider}.tar.gz")]
        renamed = directory / f"{provider}-{target}.tar.gz{suffix}"
        if renamed == path:
            continue
        print(f"  {path.name} -> {renamed.name}")
        path.rename(renamed)


if __name__ == "__main__":
    main()

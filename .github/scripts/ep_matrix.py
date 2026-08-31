#!/usr/bin/env python3
"""The execution providers we publish, and where each comes from.

Every provider is released on its own stream, because ONNX Runtime versions
its plugins separately from the runtime and from each other. A plugin declares
the oldest runtime it works against and keeps working past it, so tying one to
a runtime release would republish it for no reason.

Two sources, and the difference is only in how the artifact is obtained:

  * `build` compiles it here, from the pinned submodule.
  * `fetch` takes ONNX Runtime's own published plugin. CUDA is theirs because
    building it needs the CUDA toolkit and hours of compute: Microsoft budgets
    240 minutes on Linux and 360 on Windows, against a six hour ceiling on four
    cores, and a Windows runner has 14 GB of disk against a 2.3 GB toolkit.
  * `pypi` is the same idea against a different host. QNN is published as a
    Python wheel rather than a release asset, and building it is not an option
    at all: the Qualcomm SDK it links against is behind an authenticated
    download, while the wheel carries that SDK's runtime already licensed for
    redistribution.
"""

from __future__ import annotations

import dataclasses
import pathlib

REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
SUBMODULE = REPO_ROOT / "third_party" / "onnxruntime"

BUILD = "build"
FETCH = "fetch"
PYPI = "pypi"


@dataclasses.dataclass(frozen=True)
class Provider:
    """One execution provider, published on its own release stream."""

    name: str
    source: str
    targets: tuple[str, ...]
    # Extra flags for a `build` provider, on top of the runtime's own.
    args: tuple[str, ...] = ()
    # For a `fetch` provider: the upstream release, and its assets as
    # (build, target, asset). The build distinguishes otherwise-identical
    # providers that differ in what they need from the machine, such as the
    # CUDA toolkit version.
    upstream_tag: str = ""
    upstream_assets: tuple[tuple[str, str, str], ...] = ()
    # For a `pypi` provider, the project whose wheels we mirror.
    pypi_project: str = ""
    # Whether the upstream artifact carries libraries the plugin loads itself,
    # which have to travel with it rather than being picked out of it.
    bundles_runtime: bool = False
    # Set when the plugin is not versioned in our pinned tree, which is the
    # case for anything not built from it.
    pinned_version: str = ""
    pinned_minimum_runtime: str = ""

    @property
    def builds(self) -> tuple[str, ...]:
        """The distinct builds published, in the order they were listed."""
        seen: list[str] = []
        for build, _, _ in self.upstream_assets:
            if build and build not in seen:
                seen.append(build)
        return tuple(seen)

    def targets_for(self, build: str | None) -> tuple[str, ...]:
        if not self.builds:
            return tuple(t for _, t, _ in self.upstream_assets)
        return tuple(t for b, t, _ in self.upstream_assets if b == build)

    def asset_name(self, build: str, target: str) -> str:
        """What we publish it as. Mirrors providerAssetFileName on the Dart
        side, which has to ask for the same name."""
        stem = f"{self.name}-{build}-{target}" if build else f"{self.name}-{target}"
        return f"{stem}.tar.gz"

    @property
    def library_stem(self) -> str:
        """The library name without prefix or extension, which is what the
        build hook looks for and what the Dart provider table checks."""
        return f"onnxruntime_providers_{self.name}"

    @property
    def version(self) -> str:
        """The plugin's own version, from the pinned tree where it is built
        from that tree, and pinned here where it is not."""
        if self.pinned_version:
            return self.pinned_version
        return (SUBMODULE / f"plugin-ep-{self.name}" / "VERSION_NUMBER").read_text(
            encoding="utf-8"
        ).strip()

    @property
    def minimum_runtime(self) -> str:
        if self.pinned_minimum_runtime:
            return self.pinned_minimum_runtime
        return (
            SUBMODULE / f"plugin-ep-{self.name}" / "MIN_ONNXRUNTIME_VERSION"
        ).read_text(encoding="utf-8").strip()

    @property
    def release_tag(self) -> str:
        return f"ep-{self.name}-v{self.version}"


PROVIDERS: tuple[Provider, ...] = (
    Provider(
        name="webgpu",
        source=BUILD,
        # Everywhere Dawn reaches a GPU and compiles. Not the 32-bit Android
        # ABIs, where Vulkan is not dependable on the hardware still running
        # them, and not iOS, where Dawn's Objective-C needs manual reference
        # counting and ONNX Runtime's iOS toolchain forces ARC on.
        targets=(
            "android-arm64-v8a",
            "android-x86_64",
            "linux-x64",
            "linux-arm64",
            "macos-arm64",
            "macos-x86_64",
            "windows-x64",
            "windows-arm64",
        ),
        args=("--use_webgpu", "shared_lib"),
    ),
    Provider(
        name="cuda",
        source=FETCH,
        targets=("linux-x64", "linux-arm64", "windows-x64", "windows-arm64"),
        upstream_tag="plugin-ep-cuda/v0.1.0",
        # Both toolkits, because the choice is real. CUDA 13 is less than half
        # the size, and needs an R580 driver: an old card runs it, an
        # un-updated machine does not, and plenty of managed fleets are years
        # behind. CUDA 12 asks far less of the driver and costs the size.
        #
        # Only 13 exists for arm64 upstream, so that is not a choice there.
        upstream_assets=(
            ("cuda12", "linux-x64", "cuda_ep_cuda12_0.1.0_linux-x64.tar.gz"),
            ("cuda12", "windows-x64", "cuda_ep_cuda12_0.1.0_win-x64.zip"),
            ("cuda13", "linux-x64", "cuda_ep_cuda13_0.1.0_linux-x64.tar.gz"),
            ("cuda13", "linux-arm64", "cuda_ep_cuda13_0.1.0_linux-aarch64.tar.gz"),
            ("cuda13", "windows-x64", "cuda_ep_cuda13_0.1.0_win-x64.zip"),
            ("cuda13", "windows-arm64", "cuda_ep_cuda13_0.1.0_win-arm64.zip"),
        ),
    ),
    Provider(
        name="qnn",
        source=PYPI,
        # What the wheels cover. Not Android: there QNN is linked into a whole
        # runtime rather than published as a plugin, so it cannot layer on
        # ours and is a runtime variant question instead.
        targets=("linux-x64", "linux-arm64", "windows-x64", "windows-arm64"),
        pypi_project="onnxruntime-qnn",
        pinned_version="2.5.0",
        # onnxruntime>=1.24.2, from the wheel's own requirements.
        pinned_minimum_runtime="1.24.2",
        # The plugin dlopens libQnnHtp and friends by bare name and carries
        # RUNPATH $ORIGIN, so the Qualcomm runtime has to sit beside it. That
        # is what the wheel ships and what we repackage, licence files and all.
        bundles_runtime=True,
        # One build. The wheel filename fragment identifies the platform; the
        # Python tag is noise, since none of these are Python extensions.
        upstream_assets=(
            ("", "linux-x64", "manylinux_2_35_x86_64"),
            ("", "linux-arm64", "manylinux_2_34_aarch64"),
            ("", "windows-x64", "win_amd64"),
            ("", "windows-arm64", "win_arm64"),
        ),
    ),
)


def by_name(name: str) -> Provider:
    for provider in PROVIDERS:
        if provider.name == name:
            return provider
    raise SystemExit(f"unknown provider {name!r}")


def built() -> list[Provider]:
    return [p for p in PROVIDERS if p.source == BUILD]


def fetched() -> list[Provider]:
    """Providers taken from someone else's build, wherever it is hosted."""
    return [p for p in PROVIDERS if p.source in (FETCH, PYPI)]

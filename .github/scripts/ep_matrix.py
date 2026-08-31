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
"""

from __future__ import annotations

import dataclasses
import pathlib

REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
SUBMODULE = REPO_ROOT / "third_party" / "onnxruntime"

BUILD = "build"
FETCH = "fetch"


@dataclasses.dataclass(frozen=True)
class Provider:
    """One execution provider, published on its own release stream."""

    name: str
    source: str
    targets: tuple[str, ...]
    # Extra flags for a `build` provider, on top of the runtime's own.
    args: tuple[str, ...] = ()
    # For a `fetch` provider: the upstream release and its asset names.
    upstream_tag: str = ""
    upstream_assets: tuple[tuple[str, str], ...] = ()

    @property
    def version(self) -> str:
        """The plugin's own version, from the pinned tree."""
        return (SUBMODULE / f"plugin-ep-{self.name}" / "VERSION_NUMBER").read_text(
            encoding="utf-8"
        ).strip()

    @property
    def minimum_runtime(self) -> str:
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
        # Everywhere Dawn reaches a GPU. Not the 32-bit Android ABIs: Vulkan is
        # not dependable on the hardware still running them.
        targets=(
            "android-arm64-v8a",
            "android-x86_64",
            "ios-device-arm64",
            "ios-sim-arm64",
            "ios-sim-x86_64",
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
        # CUDA 13 rather than 12: less than half the size, at the cost of
        # needing an R580 driver. The 12 builds stay available upstream for
        # anyone who cannot move.
        upstream_assets=(
            ("linux-x64", "cuda_ep_cuda13_0.1.0_linux-x64.tar.gz"),
            ("linux-arm64", "cuda_ep_cuda13_0.1.0_linux-aarch64.tar.gz"),
            ("windows-x64", "cuda_ep_cuda13_0.1.0_win-x64.zip"),
            ("windows-arm64", "cuda_ep_cuda13_0.1.0_win-arm64.zip"),
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
    return [p for p in PROVIDERS if p.source == FETCH]

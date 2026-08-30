"""The ONNX Runtime build matrix.

Single source of truth for the build jobs and the release fan-in. Kept in Python
rather than inline YAML so test_matrix.py can enforce the invariants.
"""

from __future__ import annotations

import dataclasses
import re

# Never pass these. The first three couple the binary to a fixed model set and
# fail at load time on a user's device, the fourth removes transformer fusion,
# and the rest trade correctness surface for a few megabytes.
DENIED_FLAGS = (
    "--minimal_build",
    "--include_ops_by_config",
    "--enable_reduced_operator_type_support",
    "--disable_contrib_ops",
    "--disable_ml_ops",
    "--disable_rtti",
    "--disable_exceptions",
)

# Native only. Web sets its own because LTO does not combine well with
# Emscripten.
COMMON_NATIVE_FLAGS = (
    "--build_shared_lib",
    "--parallel",
    "--enable_lto",
    "--skip_tests",
    "--cmake_extra_defines",
    "onnxruntime_BUILD_UNIT_TESTS=OFF",
)


@dataclasses.dataclass(frozen=True)
class Config:
    """One row of the build matrix."""

    id: str
    platform: str
    arch: str
    runner: str
    args: tuple[str, ...]
    # Set until the configuration has had a green build.
    unproven: bool = False

    @property
    def is_native(self) -> bool:
        return self.platform != "web"

    def build_args(self) -> tuple[str, ...]:
        base = COMMON_NATIVE_FLAGS if self.is_native else ()
        return base + self.args


def _android(abi: str) -> Config:
    # No --use_nnapi. Deprecated in Android 15, WebGPU replaces it.
    return Config(
        id=f"android-{abi}",
        platform="android",
        arch=abi,
        runner="ubuntu-24.04",
        args=(
            "--android",
            "--android_abi", abi,
            "--android_api", "24",
            "--use_xnnpack",
        ),
    )


def _ios(name: str, sysroot: str, arch: str) -> Config:
    # The only ORT iOS prebuilt is static, which forces a podspec and defeats
    # the pure-Dart requirement, so iOS is ours to build. --no_kleidiai avoids a
    # convolution memory regression on Apple targets.
    return Config(
        id=f"ios-{name}",
        platform="ios",
        arch=arch,
        runner="macos-15",
        args=(
            "--ios",
            "--apple_sysroot", sysroot,
            "--osx_arch", arch,
            "--apple_deploy_target", "15.1",
            "--use_coreml",
            "--use_xnnpack",
            "--no_kleidiai",
        ),
        unproven=True,
    )


CONFIGURATIONS: tuple[Config, ...] = (
    # Android: all four ABIs.
    _android("arm64-v8a"),
    _android("armeabi-v7a"),
    _android("x86_64"),
    _android("x86"),

    # iOS: device plus both simulator architectures.
    _ios("device-arm64", "iphoneos", "arm64"),
    _ios("sim-arm64", "iphonesimulator", "arm64"),
    _ios("sim-x86_64", "iphonesimulator", "x86_64"),

    # macOS.
    Config(
        id="macos-arm64",
        platform="macos",
        arch="arm64",
        runner="macos-15",
        args=("--osx_arch", "arm64", "--use_coreml", "--use_xnnpack"),
    ),
    Config(
        id="macos-x86_64",
        platform="macos",
        arch="x86_64",
        # macos-13 was retired from actions/runner-images.
        runner="macos-15-intel",
        args=("--osx_arch", "x86_64", "--use_coreml", "--use_xnnpack"),
    ),

    # Linux.
    Config(
        id="linux-x64",
        platform="linux",
        arch="x86_64",
        runner="ubuntu-24.04",
        args=("--use_xnnpack", "--use_webgpu"),
    ),
    Config(
        id="linux-arm64",
        platform="linux",
        arch="arm64",
        runner="ubuntu-24.04-arm",
        args=("--use_xnnpack", "--use_webgpu"),
    ),

    # Windows.
    Config(
        id="windows-x64",
        platform="windows",
        arch="x86_64",
        runner="windows-2022",
        args=("--use_xnnpack", "--use_webgpu"),
    ),
    Config(
        id="windows-arm64",
        platform="windows",
        arch="arm64",
        runner="windows-11-arm",
        args=("--use_xnnpack", "--use_webgpu"),
    ),

    # Web. Threads need cross-origin isolation, which the embedding page may
    # not have, so the single-threaded build is a required fallback.
    Config(
        id="web-wasm-simd",
        platform="web",
        arch="wasm32",
        runner="ubuntu-24.04",
        args=("--build_wasm", "--enable_wasm_simd", "--skip_tests", "--parallel"),
    ),
    Config(
        id="web-wasm-simd-threads",
        platform="web",
        arch="wasm32",
        runner="ubuntu-24.04",
        args=(
            "--build_wasm",
            "--enable_wasm_simd",
            "--enable_wasm_threads",
            "--skip_tests",
            "--parallel",
        ),
    ),
)


def assert_complete_build(args) -> None:
    """Raises if any flag would produce an incomplete operator set."""
    for denied in DENIED_FLAGS:
        if denied in args:
            raise SystemExit(
                f"refusing to build: {denied} produces an incomplete operator "
                f"set. See DENIED_FLAGS."
            )


def select(pattern: str) -> list[Config]:
    """Returns configurations whose id matches `pattern`, or all of them."""
    if pattern in ("", "all"):
        return list(CONFIGURATIONS)
    matcher = re.compile(pattern)
    chosen = [c for c in CONFIGURATIONS if matcher.search(c.id)]
    if not chosen:
        raise SystemExit(f"no configuration matches {pattern!r}")
    return chosen


def by_id(config_id: str) -> Config:
    for config in CONFIGURATIONS:
        if config.id == config_id:
            return config
    raise SystemExit(f"unknown configuration id {config_id!r}")


@dataclasses.dataclass(frozen=True)
class Group:
    """Configurations sharing a runner, built by one job.

    Grouping is by platform, never across platforms. Android's four ABIs share a
    toolchain, an NDK install and a dependency cache, so building them in one job
    pays that setup once. Linux x64 and arm64 need different runners entirely and
    have nothing to share, so they stay apart.
    """

    id: str
    platform: str
    runner: str
    configs: tuple[Config, ...]


def group(configs: list[Config]) -> list[Group]:
    """Partitions `configs` into one job per platform and runner."""
    ordered: dict[tuple[str, str], list[Config]] = {}
    for config in configs:
        ordered.setdefault((config.platform, config.runner), []).append(config)

    # A platform split across runners keeps the configuration id, so the two
    # jobs stay distinguishable.
    platform_counts: dict[str, int] = {}
    for platform, _ in ordered:
        platform_counts[platform] = platform_counts.get(platform, 0) + 1

    groups = []
    for (platform, runner), members in ordered.items():
        name = platform if platform_counts[platform] == 1 else members[0].id
        groups.append(
            Group(id=name, platform=platform, runner=runner, configs=tuple(members))
        )
    return groups

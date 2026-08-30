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

# Every configuration, web included. Building ORT's unit tests roughly doubles
# build time and is not something we ship, and --skip_tests alone does not stop
# the targets being compiled.
COMMON_FLAGS = (
    "--parallel",
    "--skip_tests",
    "--cmake_extra_defines",
    "onnxruntime_BUILD_UNIT_TESTS=OFF",
)

# Native only. LTO does not combine well with Emscripten, and the wasm build
# produces its own artifact shape rather than a shared library.
NATIVE_ONLY_FLAGS = (
    "--build_shared_lib",
    "--enable_lto",
)


# Each component is released separately, so one component's rebuild never
# disturbs another's assets. The build hook of the matching package pins one tag.
RUNTIME = "runtime"
EP_WEBGPU = "ep-webgpu"


@dataclasses.dataclass(frozen=True)
class Config:
    """One row of the build matrix."""

    id: str
    platform: str
    arch: str
    runner: str
    args: tuple[str, ...]
    component: str = RUNTIME
    # Set until the configuration has had a green build.
    unproven: bool = False

    @property
    def is_native(self) -> bool:
        return self.platform != "web"

    @property
    def builds_shared_library(self) -> bool:
        """Whether this produces libonnxruntime rather than a plugin beside it."""
        return self.component == RUNTIME and self.is_native

    def build_args(self) -> tuple[str, ...]:
        base = COMMON_FLAGS + (NATIVE_ONLY_FLAGS if self.is_native else ())
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
            # build.py rejects an Apple framework build under any other
            # generator.
            "--cmake_generator", "Xcode",
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
        args=("--use_xnnpack", "--use_webgpu", "shared_lib"),
    ),
    Config(
        id="linux-arm64",
        platform="linux",
        arch="arm64",
        runner="ubuntu-24.04-arm",
        args=("--use_xnnpack", "--use_webgpu", "shared_lib"),
    ),

    # Windows.
    Config(
        id="windows-x64",
        platform="windows",
        arch="x86_64",
        runner="windows-2022",
        args=("--use_xnnpack", "--use_webgpu", "shared_lib"),
    ),
    Config(
        id="windows-arm64",
        platform="windows",
        arch="arm64",
        runner="windows-11-arm",
        args=(
            "--use_xnnpack",
            "--use_webgpu", "shared_lib",
            "--compile_no_warning_as_error",
            # XNNPACK's scalar fp16 microkernels include arm_fp16.h, which MSVC
            # does not ship. Disabling that one family keeps the rest of
            # XNNPACK, the same way ORT disables ARM BF16 on armeabi-v7a.
            "--cmake_extra_defines", "XNNPACK_ENABLE_ARM_FP16_SCALAR=OFF",
        ),
    ),

    # Web. Threads need cross-origin isolation, which the embedding page may
    # not have, so the single-threaded build is a required fallback.
    Config(
        id="web-wasm-simd",
        platform="web",
        arch="wasm32",
        runner="ubuntu-24.04",
        args=("--build_wasm", "--enable_wasm_simd", "--use_xnnpack"),
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
            "--use_xnnpack",
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
    component: str
    configs: tuple[Config, ...]


def group(configs: list[Config]) -> list[Group]:
    """Partitions `configs` into one job per component, platform and runner."""
    ordered: dict[tuple[str, str, str], list[Config]] = {}
    for config in configs:
        key = (config.component, config.platform, config.runner)
        ordered.setdefault(key, []).append(config)

    # A platform split across runners keeps the configuration id so the two jobs
    # stay distinguishable.
    platform_counts: dict[tuple[str, str], int] = {}
    for component, platform, _ in ordered:
        key = (component, platform)
        platform_counts[key] = platform_counts.get(key, 0) + 1

    groups = []
    for (component, platform, runner), members in ordered.items():
        one_runner = platform_counts[(component, platform)] == 1
        name = platform if one_runner else members[0].id
        if component != RUNTIME:
            name = f"{component}-{name}" if one_runner else members[0].id
        groups.append(
            Group(
                id=name,
                platform=platform,
                runner=runner,
                component=component,
                configs=tuple(members),
            )
        )
    return groups

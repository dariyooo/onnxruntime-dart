#!/usr/bin/env python3
"""Self-tests for the build matrix.

A matrix edit that breaks one of these produces binaries that fail at load time
on a user's device. Cheap to catch here, expensive to catch in the field.
"""

from __future__ import annotations

import fnmatch
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import ort_matrix as m
import package_artifact


class CompleteBuilds(unittest.TestCase):
    """Every kernel, every opset, every platform."""

    def test_no_configuration_trims_the_operator_set(self):
        for config in m.all_configurations():
            with self.subTest(config.id):
                m.assert_complete_build(config.build_args())

    def test_the_guard_actually_rejects_a_denied_flag(self):
        # A guard that has never rejected anything is not evidence.
        for denied in m.DENIED_FLAGS:
            with self.subTest(denied), self.assertRaises(SystemExit):
                m.assert_complete_build(["--build_shared_lib", denied])

    def test_every_configuration_skips_ort_unit_tests(self):
        # Building them roughly doubles build time and ships nothing. Web needs
        # this as much as native does.
        for config in m.all_configurations():
            with self.subTest(config.id):
                args = config.build_args()
                self.assertIn("--skip_tests", args)
                self.assertIn("onnxruntime_BUILD_UNIT_TESTS=OFF", args)

    def test_native_configurations_build_a_shared_library(self):
        for config in m.all_configurations():
            if config.is_native:
                with self.subTest(config.id):
                    self.assertIn("--build_shared_lib", config.build_args())

    def test_web_does_not_inherit_lto(self):
        # LTO does not combine well with Emscripten.
        for config in m.all_configurations():
            if config.is_native:
                continue
            with self.subTest(config.id):
                self.assertNotIn("--enable_lto", config.build_args())


class ArchitectureCoverage(unittest.TestCase):
    """Both architectures on every platform that has both."""

    def _arches(self, platform: str) -> set[str]:
        return {c.arch for c in m.CONFIGURATIONS if c.platform == platform}

    def test_android_covers_all_four_abis(self):
        self.assertEqual(
            self._arches("android"),
            {"arm64-v8a", "armeabi-v7a", "x86_64", "x86"},
        )

    def test_desktop_platforms_cover_x86_and_arm(self):
        for platform in ("macos", "linux", "windows"):
            with self.subTest(platform):
                self.assertEqual(self._arches(platform), {"x86_64", "arm64"})

    def test_ios_covers_device_and_both_simulators(self):
        ids = {c.id for c in m.CONFIGURATIONS if c.platform == "ios"}
        self.assertEqual(ids, {"ios-device-arm64", "ios-sim-arm64", "ios-sim-x86_64"})

    def test_web_builds_are_all_threaded(self):
        # The loader drops to one thread when the page is not cross-origin
        # isolated, so a single-threaded build would carry weight for nothing.
        for config in m.all_configurations():
            if config.platform == "web":
                with self.subTest(config.id):
                    self.assertIn("--enable_wasm_threads", config.args)

    def test_web_offers_an_accelerator_choice(self):
        # A browser cannot load a provider, so the only choice is which build
        # the app serves.
        web = {c.id for c in m.CONFIGURATIONS if c.platform == "web"}
        self.assertEqual(
            web, {"web-wasm", "web-wasm-webgpu", "web-wasm-webgpu-webnn"}
        )

    def test_web_webgpu_is_compiled_in_not_loadable(self):
        # build.py raises BuildError for shared_lib together with build_wasm.
        for config in m.all_configurations():
            if config.platform == "web" and "--use_webgpu" in config.args:
                with self.subTest(config.id):
                    self.assertIn("static_lib", config.args)
                    self.assertNotIn("shared_lib", config.args)


class WindowsWarnings(unittest.TestCase):
    """MSVC promotes warnings in ORT's own sources to errors."""

    def test_both_windows_architectures_allow_ort_warnings(self):
        # graph_flatbuffers_utils.cc trips C4267 in the training sources, so
        # only the full variant failed and only on Windows. We pin ORT and do
        # not edit it, so failing on its warnings stops the build for nothing.
        for config in m.all_configurations():
            if config.platform != "windows":
                continue
            self.assertIn("--compile_no_warning_as_error", config.args, config.id)


class Packaging(unittest.TestCase):
    """The globs that decide what ends up in an archive."""

    def _web_patterns(self) -> list[str]:
        return package_artifact.ARTIFACT_PATTERNS["web"][m.RUNTIME]["*"]

    def _matches(self, name: str) -> bool:
        return any(fnmatch.fnmatch(name, p) for p in self._web_patterns())

    def test_web_patterns_match_the_plain_build(self):
        self.assertTrue(self._matches("ort-wasm-simd-threaded.wasm"))
        self.assertTrue(self._matches("ort-wasm-simd-threaded.mjs"))

    def test_web_patterns_match_the_training_build(self):
        # The full variant enables the training APIs, which ORT puts in the
        # file name. A glob anchored on "ort-wasm" silently matches nothing,
        # and the job fails only after an hour of building.
        self.assertTrue(self._matches("ort-training-wasm-simd-threaded.wasm"))
        self.assertTrue(self._matches("ort-training-wasm-simd-threaded.mjs"))

    def test_web_patterns_do_not_match_a_native_library(self):
        self.assertFalse(self._matches("libonnxruntime.so"))
        self.assertFalse(self._matches("onnxruntime.dll"))

    def test_every_web_configuration_has_a_runtime_pattern(self):
        for config in m.all_configurations():
            if config.platform != "web":
                continue
            self.assertIn(
                m.RUNTIME,
                package_artifact.ARTIFACT_PATTERNS[config.platform],
                config.id,
            )


class Parallelism(unittest.TestCase):
    """One job per configuration.

    They were grouped by platform to share a toolchain and a dependency cache,
    until the four Android ABIs linked each other's libcpuinfo.a. Each needs its
    own dependency build directory, so a shared job only serialises work that
    could run in parallel, and runners are free on a public repository.
    """

    def test_every_configuration_is_its_own_job(self):
        ids = [c.id for c in m.all_configurations()]
        self.assertEqual(len(ids), len(set(ids)))

    def test_ids_survive_a_round_trip(self):
        # The workflow addresses jobs by id, and the test jobs download
        # artifacts named after them.
        for config in m.all_configurations():
            with self.subTest(config.id):
                self.assertEqual(m.by_id(config.id).id, config.id)


class MatrixHygiene(unittest.TestCase):
    def test_ids_are_unique(self):
        ids = [c.id for c in m.CONFIGURATIONS]
        self.assertEqual(len(ids), len(set(ids)))

    def test_runners_are_standard_not_larger(self):
        # -large and -xlarge are billed even on public repositories.
        for config in m.all_configurations():
            with self.subTest(config.id):
                self.assertFalse(
                    config.runner.endswith(("-large", "-xlarge")),
                    f"{config.runner} is a larger runner and is always charged",
                )

    def test_retired_runner_images_are_not_referenced(self):
        retired = {"macos-13", "macos-12", "ubuntu-20.04", "windows-2019"}
        for config in m.all_configurations():
            with self.subTest(config.id):
                self.assertNotIn(config.runner, retired)

    def test_android_omits_deprecated_nnapi(self):
        # Deprecated in Android 15, WebGPU replaces it.
        for config in m.all_configurations():
            if config.platform == "android":
                with self.subTest(config.id):
                    self.assertNotIn("--use_nnapi", config.build_args())

    def test_apple_builds_disable_kleidiai(self):
        # Avoids a convolution memory regression on Apple targets.
        for config in m.all_configurations():
            if config.platform == "ios":
                with self.subTest(config.id):
                    self.assertIn("--no_kleidiai", config.build_args())

    def test_select_filters_and_rejects_nonsense(self):
        self.assertEqual(len(m.select("all")), len(m.all_configurations()))
        # A platform filter picks up both variants, which is what someone
        # asking for "macos" means.
        self.assertEqual(
            {c.id for c in m.select("^macos-")},
            {
                "macos-arm64",
                "macos-x86_64",
                "macos-arm64-full",
                "macos-x86_64-full",
            },
        )
        # A variant can be selected on its own.
        self.assertEqual(
            {c.id for c in m.select("-full$")},
            {c.id for c in m.all_configurations() if c.variant == m.FULL},
        )
        with self.assertRaises(SystemExit):
            m.select("no-such-platform")

    def test_by_id_round_trips_every_configuration(self):
        for config in m.all_configurations():
            with self.subTest(config.id):
                self.assertEqual(m.by_id(config.id).id, config.id)
        with self.assertRaises(SystemExit):
            m.by_id("nope")


if __name__ == "__main__":
    unittest.main(verbosity=2)

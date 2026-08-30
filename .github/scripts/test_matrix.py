#!/usr/bin/env python3
"""Self-tests for the build matrix.

A matrix edit that breaks one of these produces binaries that fail at load time
on a user's device. Cheap to catch here, expensive to catch in the field.
"""

from __future__ import annotations

import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import ort_matrix as m


class CompleteBuilds(unittest.TestCase):
    """Every kernel, every opset, every platform."""

    def test_no_configuration_trims_the_operator_set(self):
        for config in m.CONFIGURATIONS:
            with self.subTest(config.id):
                m.assert_complete_build(config.build_args())

    def test_the_guard_actually_rejects_a_denied_flag(self):
        # A guard that has never rejected anything is not evidence.
        for denied in m.DENIED_FLAGS:
            with self.subTest(denied), self.assertRaises(SystemExit):
                m.assert_complete_build(["--build_shared_lib", denied])

    def test_native_configurations_carry_the_common_flags(self):
        for config in m.CONFIGURATIONS:
            if not config.is_native:
                continue
            with self.subTest(config.id):
                args = config.build_args()
                self.assertIn("--build_shared_lib", args)
                self.assertIn("--skip_tests", args)

    def test_web_does_not_inherit_lto(self):
        # LTO does not combine well with Emscripten.
        for config in m.CONFIGURATIONS:
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

    def test_web_ships_threaded_and_unthreaded(self):
        web = [c for c in m.CONFIGURATIONS if c.platform == "web"]
        threaded = [c for c in web if "--enable_wasm_threads" in c.args]
        # The single-threaded build is a required fallback, not an option.
        self.assertEqual(len(threaded), 1)
        self.assertEqual(len(web) - len(threaded), 1)


class Grouping(unittest.TestCase):
    """One job per platform and runner. Never two platforms in one job."""

    def setUp(self):
        self.groups = m.group(list(m.CONFIGURATIONS))

    def test_every_configuration_is_built_exactly_once(self):
        built = [c.id for g in self.groups for c in g.configs]
        self.assertEqual(sorted(built), sorted(c.id for c in m.CONFIGURATIONS))
        self.assertEqual(len(built), len(set(built)))

    def test_a_job_never_mixes_platforms(self):
        for g in self.groups:
            with self.subTest(g.id):
                self.assertEqual({c.platform for c in g.configs}, {g.platform})

    def test_a_job_never_mixes_runners(self):
        # Grouping exists to share a toolchain and dependency cache, which only
        # works on one machine.
        for g in self.groups:
            with self.subTest(g.id):
                self.assertEqual({c.runner for c in g.configs}, {g.runner})

    def test_group_ids_are_unique(self):
        ids = [g.id for g in self.groups]
        self.assertEqual(len(ids), len(set(ids)))

    def test_platforms_sharing_a_runner_are_one_job(self):
        by_platform = {}
        for g in self.groups:
            by_platform.setdefault(g.platform, []).append(g)
        # Android and web cross-compile from one host, so each is a single job.
        self.assertEqual(len(by_platform["android"]), 1)
        self.assertEqual(len(by_platform["web"]), 1)
        self.assertEqual(len(by_platform["ios"]), 1)
        # These need different machines per architecture.
        for platform in ("linux", "windows", "macos"):
            self.assertEqual(len(by_platform[platform]), 2)

    def test_single_configuration_groups_keep_the_configuration_id(self):
        # Test jobs download artifacts by these names.
        for g in self.groups:
            if len(g.configs) == 1:
                with self.subTest(g.id):
                    self.assertEqual(g.id, g.configs[0].id)


class MatrixHygiene(unittest.TestCase):
    def test_ids_are_unique(self):
        ids = [c.id for c in m.CONFIGURATIONS]
        self.assertEqual(len(ids), len(set(ids)))

    def test_runners_are_standard_not_larger(self):
        # -large and -xlarge are billed even on public repositories.
        for config in m.CONFIGURATIONS:
            with self.subTest(config.id):
                self.assertFalse(
                    config.runner.endswith(("-large", "-xlarge")),
                    f"{config.runner} is a larger runner and is always charged",
                )

    def test_retired_runner_images_are_not_referenced(self):
        retired = {"macos-13", "macos-12", "ubuntu-20.04", "windows-2019"}
        for config in m.CONFIGURATIONS:
            with self.subTest(config.id):
                self.assertNotIn(config.runner, retired)

    def test_android_omits_deprecated_nnapi(self):
        # Deprecated in Android 15, WebGPU replaces it.
        for config in m.CONFIGURATIONS:
            if config.platform == "android":
                with self.subTest(config.id):
                    self.assertNotIn("--use_nnapi", config.build_args())

    def test_apple_builds_disable_kleidiai(self):
        # Avoids a convolution memory regression on Apple targets.
        for config in m.CONFIGURATIONS:
            if config.platform == "ios":
                with self.subTest(config.id):
                    self.assertIn("--no_kleidiai", config.build_args())

    def test_select_filters_and_rejects_nonsense(self):
        self.assertEqual(len(m.select("all")), len(m.CONFIGURATIONS))
        self.assertEqual({c.id for c in m.select("^macos-")},
                         {"macos-arm64", "macos-x86_64"})
        with self.assertRaises(SystemExit):
            m.select("no-such-platform")

    def test_by_id_round_trips_every_configuration(self):
        for config in m.CONFIGURATIONS:
            with self.subTest(config.id):
                self.assertIs(m.by_id(config.id), config)
        with self.assertRaises(SystemExit):
            m.by_id("nope")


if __name__ == "__main__":
    unittest.main(verbosity=2)

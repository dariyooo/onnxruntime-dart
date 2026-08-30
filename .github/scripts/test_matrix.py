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


class Grouping(unittest.TestCase):
    """One job per component, platform and runner. Never two platforms in one."""

    def setUp(self):
        self.groups = m.group(m.all_configurations())

    def test_every_configuration_is_built_exactly_once(self):
        built = [c.id for g in self.groups for c in g.configs]
        self.assertEqual(
            sorted(built), sorted(c.id for c in m.all_configurations())
        )
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
        # Counted per variant, since base and full are always separate jobs.
        by_platform = {}
        for g in self.groups:
            if g.variant != m.BASE:
                continue
            by_platform.setdefault(g.platform, []).append(g)
        # Android, iOS and web cross-compile from one host each.
        for platform in ("android", "ios", "web"):
            self.assertEqual(len(by_platform[platform]), 1, platform)
        # These need a different machine per architecture.
        for platform in ("linux", "windows", "macos"):
            self.assertEqual(len(by_platform[platform]), 2, platform)

    def test_single_configuration_groups_keep_the_configuration_id(self):
        # Test jobs download artifacts by these names.
        for g in self.groups:
            if len(g.configs) == 1:
                with self.subTest(g.id):
                    self.assertEqual(g.id, g.configs[0].id)


class Variants(unittest.TestCase):
    """Two libraries per platform: the standard one, and one with the
    capabilities that cannot be loaded at run time."""

    def test_every_base_configuration_has_a_full_counterpart(self):
        every = m.all_configurations()
        base = {c.id for c in every if c.variant == m.BASE}
        full = {c.id.removesuffix("-full") for c in every if c.variant == m.FULL}
        self.assertEqual(base, full)

    def test_full_adds_only_what_cannot_be_loaded(self):
        # Training is behind an #ifdef, extensions compiles in as a static
        # library, and the EP interfaces are linked into the core. None of the
        # three can be a separate download.
        for config in m.all_configurations():
            if config.variant != m.FULL:
                continue
            with self.subTest(config.id):
                for flag in m.FULL_ONLY_FLAGS:
                    self.assertIn(flag, config.args)

    def test_base_carries_none_of_them(self):
        for config in m.all_configurations():
            if config.variant != m.BASE:
                continue
            with self.subTest(config.id):
                for flag in m.FULL_ONLY_FLAGS:
                    self.assertNotIn(flag, config.args)

    def test_full_is_a_superset_of_its_base(self):
        # Same platform, same providers, same operators. Only additions.
        for base in m.CONFIGURATIONS:
            full = m.by_id(f"{base.id}-full")
            with self.subTest(base.id):
                self.assertEqual(full.platform, base.platform)
                self.assertEqual(full.arch, base.arch)
                self.assertEqual(full.runner, base.runner)
                for flag in base.args:
                    self.assertIn(flag, full.args)

    def test_a_job_never_mixes_variants(self):
        # Building both in one job would double its wall clock for no shared
        # work: the flags differ, so nothing is reused.
        for g in m.group(m.all_configurations()):
            with self.subTest(g.id):
                self.assertEqual({c.variant for c in g.configs}, {g.variant})


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

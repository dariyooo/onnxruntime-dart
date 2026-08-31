#!/usr/bin/env python3
"""Self-tests for the build matrix.

A matrix edit that breaks one of these produces binaries that fail at load time
on a user's device. Cheap to catch here, expensive to catch in the field.
"""

from __future__ import annotations

import fnmatch
import os
import re
import pathlib
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import ep_matrix
import ort_matrix as m

REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
import package_artifact
import release_identity


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


class ReleaseIdentity(unittest.TestCase):
    """The release is named for whatever ONNX Runtime commit is pinned."""

    @staticmethod
    def _repo(tag=None, version="1.29.0"):
        directory = pathlib.Path(tempfile.mkdtemp())
        (directory / "VERSION_NUMBER").write_text(version + "\n", encoding="utf-8")

        def run(*args):
            subprocess.run(
                ("git", "-C", str(directory)) + args, check=True, capture_output=True
            )

        run("init", "-q")
        run("config", "user.email", "test@example.com")
        run("config", "user.name", "test")
        run("add", ".")
        run("commit", "-qm", "pin")
        if tag:
            run("tag", tag)
        return directory

    def test_a_release_tag_names_the_release(self):
        self.assertEqual(
            release_identity.identity(self._repo(tag="v1.29.0")), ("v1.29.0", False)
        )

    def test_an_untagged_commit_is_named_for_itself_and_is_a_prerelease(self):
        # Trying an upstream fix that is not in a release yet must produce
        # something that cannot be mistaken for a version.
        version, prerelease = release_identity.identity(self._repo())
        self.assertTrue(prerelease)
        self.assertTrue(version.startswith("v1.29.0-g"), version)

    def test_a_tag_that_is_not_a_version_is_ignored(self):
        # Upstream carries tags other than releases. Only vX.Y.Z names one.
        version, prerelease = release_identity.identity(self._repo(tag="rel-1.29.0"))
        self.assertTrue(prerelease)
        self.assertIn("-g", version)

    def test_the_version_comes_from_the_pinned_tree(self):
        version, _ = release_identity.identity(self._repo(version="1.30.1"))
        self.assertTrue(version.startswith("v1.30.1-g"), version)


class ProviderTargets(unittest.TestCase):
    """The Dart provider table and the build matrix must agree.

    onnxruntime_ep refuses a provider the target has no build for, so a target
    listed in Dart but absent from the matrix means a download that 404s, and
    one built but not listed means a plugin nobody can install.
    """

    @staticmethod
    def _claimed(provider: str) -> set[str]:
        """Targets the Dart table lists for `provider`.

        Arms are read generically because several providers can share one:
        `OrtProvider.cuda || OrtProvider.tensorrt => const [...]`.
        """
        source = (
            REPO_ROOT / "packages" / "onnxruntime_hook" / "lib" / "src" / "target.dart"
        ).read_text(encoding="utf-8")
        # Only the targets getter. Others switch on the same enum and would
        # otherwise be read as targets, which is how "cuda13" once became one.
        source = source.split("List<String> get targets")[1].split(
            "bool isAvailableOn"
        )[0]
        for arm in re.finditer(
            r"((?:OrtProvider\.\w+\s*\|\|\s*)*OrtProvider\.\w+)\s*=>\s*const \[([^\]]*)\]",
            source,
        ):
            names = re.findall(r"OrtProvider\.(\w+)", arm.group(1))
            if provider in names:
                return set(re.findall(r"'([^']+)'", arm.group(2)))
        raise AssertionError(f"no targets listed for {provider}")

    @staticmethod
    def _built(flag: str) -> set[str]:
        return {
            c.id
            for c in m.all_configurations()
            if c.variant == m.BASE and flag in " ".join(c.args) and c.platform != "web"
        }

    def test_webgpu_targets_match_the_matrix(self):
        self.assertEqual(self._claimed("webgpu"), self._built("--use_webgpu"))

    def test_redistributed_providers_name_real_targets(self):
        # CUDA and TensorRT are redistributed rather than built, so they are
        # not in the matrix. They must still name targets we actually support.
        every = {c.id for c in m.all_configurations() if c.variant == m.BASE}
        for provider in ("cuda", "tensorrt", "qnn"):
            for target in self._claimed(provider):
                self.assertIn(target, every, f"{provider} claims {target}")


class Providers(unittest.TestCase):
    """Execution providers, each on its own release stream."""

    def test_versions_come_from_the_pinned_tree(self):
        # Read, never written down: a plugin's version is ONNX Runtime's to
        # choose, and the Dart package that installs it carries the same one.
        for provider in ep_matrix.PROVIDERS:
            self.assertRegex(provider.version, r"^\d+\.\d+\.\d+$")
            self.assertEqual(
                provider.release_tag, f"ep-{provider.name}-v{provider.version}"
            )

    def test_every_provider_outlives_the_runtime_we_ship(self):
        ours = (
            ep_matrix.SUBMODULE / "VERSION_NUMBER"
        ).read_text(encoding="utf-8").strip()
        for provider in ep_matrix.PROVIDERS:
            self.assertLessEqual(
                tuple(int(x) for x in provider.minimum_runtime.split(".")),
                tuple(int(x) for x in ours.split(".")),
                provider.name,
            )

    def test_targets_are_ones_we_support(self):
        every = {c.id for c in m.all_configurations() if c.variant == m.BASE}
        for provider in ep_matrix.PROVIDERS:
            self.assertTrue(provider.targets, provider.name)
            for target in provider.targets:
                self.assertIn(target, every, f"{provider.name} -> {target}")

    def test_a_built_provider_is_built_where_the_runtime_matrix_says(self):
        # WebGPU comes out of an ONNX Runtime build, so it can only exist for a
        # target that build runs on. Only the shared_lib builds: the web ones
        # compile it in, where there is no library to load and nothing to ship
        # separately.
        webgpu = ep_matrix.by_name("webgpu")
        matrix = {
            c.id
            for c in m.all_configurations()
            if c.variant == m.BASE
            and "shared_lib" in c.args
            and "--use_webgpu" in c.args
        }
        self.assertEqual(set(webgpu.targets), matrix)

    def test_a_fetched_provider_names_an_asset_for_every_target(self):
        # Across all its builds, a fetched provider must cover every target it
        # claims. One build need not: CUDA 12 has no arm64 upstream.
        for provider in ep_matrix.fetched():
            named = {target for _, target, _ in provider.upstream_assets}
            self.assertEqual(named, set(provider.targets), provider.name)
            self.assertTrue(provider.upstream_tag, provider.name)


    def test_cuda_ships_both_toolkits(self):
        # CUDA 13 needs an R580 driver, which a machine nobody has updated
        # will not have, so the older toolkit has to stay available.
        cuda = ep_matrix.by_name("cuda")
        self.assertEqual(cuda.builds, ("cuda12", "cuda13"))
        self.assertEqual(
            set(cuda.targets_for("cuda12")), {"linux-x64", "windows-x64"}
        )

    def test_the_dart_side_agrees_about_the_builds(self):
        source = (
            REPO_ROOT / "packages" / "onnxruntime_hook" / "lib" / "src" / "target.dart"
        ).read_text(encoding="utf-8")
        for provider in ep_matrix.fetched():
            for build in provider.builds:
                self.assertIn(f"'{build}'", source, f"{provider.name} {build}")


class WebPackages(unittest.TestCase):
    """The Flutter web packages and the wasm builds must agree.

    Each package hardcodes the file name Flutter will serve, and that name is
    ONNX Runtime's, set by which features are compiled in. Two of the three
    builds produce the same file name with different contents, which is why
    each build is its own package rather than one package with three assets.
    """

    WEB = {
        "onnxruntime_web": ("web-wasm", "ort-wasm-simd-threaded"),
        "onnxruntime_web_webgpu": (
            "web-wasm-webgpu",
            "ort-wasm-simd-threaded.asyncify",
        ),
        "onnxruntime_web_webgpu_webnn": (
            "web-wasm-webgpu-webnn",
            "ort-wasm-simd-threaded.asyncify",
        ),
    }

    def _asset_source(self, package: str) -> str:
        return (
            REPO_ROOT / "packages" / package / "lib" / "src" / "asset.dart"
        ).read_text(encoding="utf-8")

    def test_every_web_build_has_a_package(self):
        built = {
            c.id for c in m.all_configurations()
            if c.platform == "web" and c.variant == m.BASE
        }
        claimed = {build for build, _ in self.WEB.values()}
        self.assertEqual(claimed, built)

    def test_each_package_names_its_own_build(self):
        for package, (build, _) in self.WEB.items():
            self.assertIn(f"'{build}'", self._asset_source(package), package)

    def test_asset_urls_use_the_package_own_name(self):
        # Flutter serves a package's assets under its own name. Getting this
        # wrong yields a 404 at run time and nothing at build time.
        for package in self.WEB:
            source = self._asset_source(package)
            self.assertIn(f"assets/packages/{package}/assets/", source, package)

    def test_file_names_match_what_the_build_produces(self):
        for package, (_, stem) in self.WEB.items():
            source = self._asset_source(package)
            self.assertIn(f"{stem}.wasm", source, package)
            self.assertIn(f"{stem}.mjs", source, package)

    def test_the_colliding_builds_are_separate_packages(self):
        # webgpu and webgpu-webnn produce the same file name and different
        # binaries, so one package could not carry both.
        stems = [stem for _, stem in self.WEB.values()]
        self.assertNotEqual(len(set(stems)), len(stems))


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

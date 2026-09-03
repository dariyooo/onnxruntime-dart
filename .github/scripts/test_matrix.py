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
import extensions_matrix
import ort_matrix as m

REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
import package_artifact
import release_identity
import binary_arch
import rename_release_assets


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

    def test_an_untagged_commit_is_still_named_for_its_version(self):
        # It is a prerelease, and it is still named for the version, because
        # the build hook derives what it asks for from a package version and
        # cannot know a commit. A name with a commit in it is one nothing
        # looks for.
        version, prerelease = release_identity.identity(self._repo())
        self.assertTrue(prerelease)
        self.assertEqual(version, "v1.29.0")

    def test_a_tag_that_is_not_a_version_is_ignored(self):
        # Upstream carries tags other than releases. Only vX.Y.Z names one, so
        # this is a prerelease, but the name does not change.
        version, prerelease = release_identity.identity(self._repo(tag="rel-1.29.0"))
        self.assertTrue(prerelease)
        self.assertEqual(version, "v1.29.0")

    def test_the_version_comes_from_the_pinned_tree(self):
        version, _ = release_identity.identity(self._repo(version="1.30.1"))
        self.assertEqual(version, "v1.30.1")

    def test_a_shallow_checkout_names_the_release_the_same(self):
        # CI checks out submodules without tags, so `git describe` finds
        # nothing even when the commit is exactly a release tag. That once
        # renamed the release and made the base package uninstallable. The name
        # must not depend on whether tags were fetched.
        tagged = release_identity.identity(self._repo(tag="v1.29.0"))[0]
        shallow = release_identity.identity(self._repo())[0]
        self.assertEqual(tagged, shallow)

    def test_the_runtime_release_is_what_the_installer_asks_for(self):
        # The whole point. onnxruntime_binaries installs from a tag built out
        # of its own pubspec version, so the publisher has to produce that
        # exact name or nothing can install.
        pubspec = (
            REPO_ROOT / "packages" / "onnxruntime_binaries" / "pubspec.yaml"
        ).read_text(encoding="utf-8")
        installed = re.search(
            r"^version:\s*(\S+)\s*$", pubspec, re.MULTILINE
        ).group(1)
        self.assertEqual(
            release_identity.release_tag("runtime"),
            f"runtime-v{installed}",
            f"the hook would look for runtime-v{installed}",
        )


class PackageVersions(unittest.TestCase):
    """A package that ships upstream binaries is versioned as those binaries.

    Nothing here is a number someone chose. The point is that a reader can tell
    which ONNX Runtime a package carries by looking at it, and that bumping the
    submodule without bumping the pubspecs is caught here rather than by a
    release nobody can install.
    """

    @staticmethod
    def _version(package: str) -> str:
        pubspec = (REPO_ROOT / "packages" / package / "pubspec.yaml").read_text(
            encoding="utf-8"
        )
        return re.search(r"^version:\s*(\S+)\s*$", pubspec, re.MULTILINE).group(1)

    def test_the_runtime_packages_carry_the_runtime_version(self):
        upstream = (
            REPO_ROOT / "third_party" / "onnxruntime" / "VERSION_NUMBER"
        ).read_text(encoding="utf-8").strip()

        for package in (
            "onnxruntime_binaries",
            "onnxruntime_hook",
            "onnxruntime_web",
            "onnxruntime_web_webgpu",
            "onnxruntime_web_webgpu_webnn",
        ):
            self.assertEqual(self._version(package), upstream, package)

    def test_the_extensions_package_carries_the_extensions_version(self):
        self.assertEqual(
            self._version("onnxruntime_extensions_binaries"),
            extensions_matrix.version(),
        )

    def test_each_provider_package_carries_its_plugin_version(self):
        for provider in ep_matrix.PROVIDERS:
            self.assertEqual(
                self._version(f"onnxruntime_ep_{provider.name}_binaries"),
                provider.version,
                provider.name,
            )

    def test_the_bindings_say_which_runtime_they_were_generated_against(self):
        # The one package with a version of its own, because it is the API
        # rather than a binary. It still names the runtime it was generated
        # against, in the build metadata, so the pairing is visible.
        upstream = (
            REPO_ROOT / "third_party" / "onnxruntime" / "VERSION_NUMBER"
        ).read_text(encoding="utf-8").strip()
        self.assertTrue(
            self._version("onnxruntime_dart").endswith(f"+onnxruntime-{upstream}"),
            self._version("onnxruntime_dart"),
        )


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
    def _built(component: str) -> set[str]:
        """Targets the matrix builds `component` for, named as the runtime
        configuration each is derived from."""
        suffix = "-" + component.removeprefix("ep-")
        return {
            c.id.removesuffix(suffix)
            for c in m.all_configurations()
            if c.component == component
        }

    def test_webgpu_targets_match_the_matrix(self):
        self.assertEqual(self._claimed("webgpu"), self._built(m.EP_WEBGPU))

    def test_a_built_provider_is_packaged_everywhere_it_is_claimed(self):
        # Building with the flag is not the same as collecting the library
        # afterwards. A platform can compile the provider and have no pattern
        # to pick it up, which publishes nothing and 404s at install time
        # while every other check still passes.
        import package_artifact

        for provider in ep_matrix.built():
            component = f"ep-{provider.name}"
            for target in provider.targets:
                config = next(
                    (c for c in m.all_configurations() if c.id == target), None
                )
                self.assertIsNotNone(config, f"{target} is not a configuration")
                patterns = package_artifact.ARTIFACT_PATTERNS[config.platform]
                self.assertIn(
                    component,
                    patterns,
                    f"{provider.name} claims {target}, but nothing collects "
                    f"its library on {config.platform}",
                )

    def test_redistributed_providers_name_real_targets(self):
        # CUDA and TensorRT are redistributed rather than built, so they are
        # not in the matrix. They must still name targets we actually support.
        every = {c.id for c in m.all_configurations() if c.variant == m.BASE}
        for provider in ("cuda", "tensorrt", "qnn"):
            for target in self._claimed(provider):
                self.assertIn(target, every, f"{provider} claims {target}")

    def test_everything_names_the_extensions_release_the_same(self):
        # Three places have an opinion: the publisher, release_identity, which
        # anything looking for the release asks, and the build hook, which
        # derives the tag from the package version. The last time these were
        # allowed to differ, the release existed under a name nothing looked
        # for.
        import extensions_matrix
        import release_identity

        self.assertEqual(
            release_identity.release_tag("extensions"),
            extensions_matrix.release_tag(),
        )

        pubspec = (
            REPO_ROOT / "packages" / "onnxruntime_extensions_binaries" / "pubspec.yaml"
        ).read_text(encoding="utf-8")
        installed = re.search(
            r"^version:\s*(\S+)\s*$", pubspec, re.MULTILINE
        ).group(1)
        self.assertEqual(
            f"extensions-v{installed}",
            extensions_matrix.release_tag(),
            f"the hook would look for extensions-v{installed}",
        )

    def test_the_dart_side_agrees_about_the_targets(self):
        # The hook asks for an asset per target from this table, so a target
        # here that the matrix does not publish is a download that will 404,
        # and one missing here is a platform silently left without a provider.
        for provider in ep_matrix.fetched():
            self.assertEqual(
                self._claimed(provider.name),
                set(provider.targets),
                provider.name,
            )


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

    def test_the_publisher_and_the_installer_name_the_same_release(self):
        # The release name is derived twice, in two languages: the workflow
        # asks release_identity, and the build hook reads the package's own
        # pubspec. Nothing makes those meet at runtime, so a disagreement is
        # not an error, it is a 404 at install time for whoever depends on the
        # package. This is the only thing that makes them meet.
        import release_identity

        for provider in ep_matrix.PROVIDERS:
            published = release_identity.provider_version(f"ep-{provider.name}")
            self.assertEqual(published, provider.version, provider.name)

            pubspec = (
                REPO_ROOT
                / "packages"
                / f"onnxruntime_ep_{provider.name}_binaries"
                / "pubspec.yaml"
            ).read_text(encoding="utf-8")
            installed = re.search(
                r"^version:\s*(\S+)\s*$", pubspec, re.MULTILINE
            ).group(1)
            self.assertEqual(
                f"ep-{provider.name}-v{installed}",
                provider.release_tag,
                f"{provider.name}: the hook would look for "
                f"ep-{provider.name}-v{installed}, the workflow publishes "
                f"{provider.release_tag}",
            )

    def test_the_runtime_publishes_the_name_the_hook_installs(self):
        # The runtime used to be the one component named for the target alone,
        # which read fine and sorted badly beside every other asset. Both sides
        # now put the component first, and this is what keeps them there.
        import rename_release_assets  # noqa: PLC0415

        with tempfile.TemporaryDirectory() as directory:
            staged = pathlib.Path(directory)
            for name in ("linux-x64.tar.gz", "linux-x64-full.tar.gz", "headers.tar.gz"):
                (staged / name).touch()

            sys.argv = ["", str(staged), "runtime"]
            rename_release_assets.main()

            self.assertEqual(
                {p.name for p in staged.iterdir()},
                {"base-linux-x64.tar.gz", "full-linux-x64.tar.gz", "headers.tar.gz"},
            )

        source = (
            REPO_ROOT / "packages" / "onnxruntime_hook" / "lib" / "src" / "target.dart"
        ).read_text(encoding="utf-8")
        self.assertIn("'base-$targetId.tar.gz'", source)

    def test_the_installer_and_the_publisher_name_the_same_asset(self):
        # The tag is not the only name that has to agree. A provider built
        # through the runtime pipeline produces <target>-<provider>.tar.gz,
        # because its configuration ids already end in the provider name, and
        # a mirrored one produces <provider>-<target>.tar.gz. The hook asks for
        # the second, so the first is renamed before publishing. This pins both
        # halves: the shape the hook builds, and the shape the rename produces.
        source = (
            REPO_ROOT / "packages" / "onnxruntime_hook" / "lib" / "src" / "target.dart"
        ).read_text(encoding="utf-8")
        self.assertIn("'$provider-$targetId.tar.gz'", source)
        self.assertIn("'$provider-$build-$targetId.tar.gz'", source)

        sys.path.insert(0, str(REPO_ROOT / ".github" / "scripts"))
        import rename_release_assets  # noqa: PLC0415

        with tempfile.TemporaryDirectory() as directory:
            staged = pathlib.Path(directory)
            for provider in ep_matrix.PROVIDERS:
                for target in provider.targets:
                    (staged / f"{target}-{provider.name}.tar.gz").touch()

            for provider in ep_matrix.PROVIDERS:
                sys.argv = ["", str(staged), provider.name]
                rename_release_assets.main()

            for provider in ep_matrix.PROVIDERS:
                for target in provider.targets:
                    self.assertTrue(
                        (staged / f"{provider.name}-{target}.tar.gz").is_file(),
                        f"{provider.name}-{target}.tar.gz is not what publishing "
                        f"would leave behind",
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
        # WebGPU comes out of an ONNX Runtime build, so it can only exist for
        # a target that build runs on. Its own configuration per target, never
        # the web ones: there it is compiled into the wasm, with no library to
        # load and nothing to ship separately.
        webgpu = ep_matrix.by_name("webgpu")
        matrix = {
            c.id.removesuffix("-webgpu")
            for c in m.all_configurations()
            if c.component == m.EP_WEBGPU
        }
        self.assertEqual(set(webgpu.targets), matrix)
        self.assertFalse([c for c in m.all_configurations()
                          if c.component == m.EP_WEBGPU and c.platform == "web"])

    def test_a_fetched_provider_names_an_asset_for_every_target(self):
        # Across all its builds, a fetched provider must cover every target it
        # claims. One build need not: CUDA 12 has no arm64 upstream.
        for provider in ep_matrix.fetched():
            named = {target for _, target, _ in provider.upstream_assets}
            self.assertEqual(named, set(provider.targets), provider.name)
            # Whichever host it comes from has to be identified.
            source = (
                provider.pypi_project
                if provider.source == ep_matrix.PYPI
                else provider.upstream_tag
            )
            self.assertTrue(source, provider.name)

    def test_a_library_that_is_not_installed_resolves_to_nothing(self):
        # TensorRT is in the provider table with no package behind it, because
        # upstream ships only the bridge ABI. That is safe rather than broken:
        # a code asset that was not installed falls back to a process-wide
        # symbol lookup, and every provider exports the same entry point, so
        # the file name is checked before a path is believed.
        lookup = (
            REPO_ROOT / "packages" / "onnxruntime_dart" / "lib" / "src" / "ffi"
            / "library_lookup.dart"
        ).read_text(encoding="utf-8")
        self.assertIn("fileName.contains(stem)", lookup)

        table = (
            REPO_ROOT / "packages" / "onnxruntime_hook" / "lib" / "src"
            / "target.dart"
        ).read_text(encoding="utf-8")
        self.assertIn("tensorrt(", table)

    def test_the_base_package_names_no_provider_package(self):
        # The layering. A provider package declares its own asset and finds it
        # with loadedLibraryPath, so adding one is a new package rather than an
        # edit to the base.
        base = REPO_ROOT / "packages" / "onnxruntime_dart" / "lib"
        for source in base.rglob("*.dart"):
            self.assertNotIn(
                "package:onnxruntime_ep_",
                source.read_text(encoding="utf-8"),
                f"{source.name} names a provider package",
            )

    def test_qnn_is_mirrored_whole(self):
        # The plugin dlopens the Qualcomm runtime by bare name, so unlike CUDA
        # the sibling libraries are part of the artifact rather than the
        # machine's job. It ships one build, so no build appears in the name.
        qnn = ep_matrix.by_name("qnn")
        self.assertEqual(qnn.source, ep_matrix.PYPI)
        self.assertTrue(qnn.bundles_runtime)
        self.assertEqual(qnn.builds, ())
        self.assertEqual(qnn.asset_name("", "linux-x64"), "qnn-linux-x64.tar.gz")
        # Not versioned in our tree, because it is not built from it.
        self.assertFalse((ep_matrix.SUBMODULE / "plugin-ep-qnn").exists())
        self.assertTrue(qnn.pinned_version)

    def test_qnn_does_not_claim_android(self):
        # There QNN is linked into a whole runtime rather than published as a
        # plugin, so it cannot layer on ours.
        qnn = ep_matrix.by_name("qnn")
        self.assertFalse([t for t in qnn.targets if t.startswith("android")])

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
                "macos-arm64-webgpu",
                "macos-x86_64-webgpu",
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


class Extensions(unittest.TestCase):
    """The operator library, which is its own project and its own pipeline."""

    def setUp(self):
        import extensions_matrix

        self.ext = extensions_matrix

    def test_it_covers_every_native_runtime_target(self):
        # An operator library is only useful beside a runtime for the same
        # target, and a target with a runtime and no operators is a download
        # that 404s at install time.
        self.assertEqual(
            sorted(self.ext.targets()), sorted(self.ext.runtime_targets())
        )

    def test_it_does_not_claim_the_web(self):
        # Upstream refuses a shared library under Emscripten: there the
        # operators are compiled into the runtime instead of loaded beside it.
        self.assertFalse([t for t in self.ext.targets() if t.startswith("web")])

    def test_the_version_comes_from_the_pinned_source(self):
        # Upstream tags v0.14.0 on a commit whose version.txt says 0.15.0, and
        # the built library follows the file, so the file is what we publish.
        version = self.ext.version()
        pubspec = (
            REPO_ROOT / "packages" / "onnxruntime_extensions_binaries" / "pubspec.yaml"
        ).read_text(encoding="utf-8")
        self.assertIn(f"version: {version}", pubspec)

    def test_the_dart_side_agrees_about_the_targets(self):
        source = (
            REPO_ROOT / "packages" / "onnxruntime_hook" / "lib" / "src" / "target.dart"
        ).read_text(encoding="utf-8")
        self.assertIn("abstract final class OrtExtensions", source)
        self.assertIn("'ortextensions'", source)

    def test_it_has_its_own_pipeline(self):
        import yaml

        ci = yaml.safe_load(
            (REPO_ROOT / ".github" / "workflows" / "ci.yml").read_text(
                encoding="utf-8"
            )
        )
        self.assertTrue(
            any(
                str(job.get("uses", "")).endswith("build-extensions.yml")
                for job in ci["jobs"].values()
            ),
            "nothing in ci builds the extensions library",
        )


class Pipelines(unittest.TestCase):
    """Every thing that ships on its own is built on its own.

    A provider sharing a pipeline with a runtime means the provider can stop
    the runtime from being built at all, which is what happened when WebGPU was
    a flag on the runtime configurations rather than configurations of its own.
    """

    @staticmethod
    def _ci() -> dict:
        import yaml

        return yaml.safe_load(
            (REPO_ROOT / ".github" / "workflows" / "ci.yml").read_text(
                encoding="utf-8"
            )
        )

    def test_nothing_publishes_except_on_a_tag(self):
        """Pushing a branch builds and tests. Only a tag publishes.

        Landing on main is what proves a pin across the whole matrix, and that
        has to be able to happen freely. Publishing is the other thing: a
        release is outward facing and cannot be withdrawn once somebody has
        installed from it, so it waits for a tag, which is deliberate in a way
        that merging is not.

        This once read the other way round and asserted that publishing was
        gated on main, which is exactly how pushing a branch came to publish.
        """
        import yaml

        checked = 0
        for path in sorted((REPO_ROOT / ".github" / "workflows").glob("*.yml")):
            workflow = yaml.safe_load(path.read_text(encoding="utf-8"))
            for name, job in (workflow.get("jobs") or {}).items():
                steps = job.get("steps") or []
                # Matched on what a step does, not on what it is called, so a
                # new publisher cannot slip past by being named something else.
                publishes = [
                    step
                    for step in steps
                    if "publish" in str(step.get("name", "")).lower()
                    or "release create" in str(step.get("run", ""))
                    or "release upload" in str(step.get("run", ""))
                    or "publish_" in str(step.get("run", ""))
                ]
                if not publishes:
                    continue

                guard = str(job.get("if", "")) + "".join(
                    str(step.get("if", "")) for step in publishes
                )
                with self.subTest(workflow=path.name, job=name):
                    self.assertIn(
                        "refs/tags/",
                        guard,
                        f"{path.name}:{name} publishes without being on a tag",
                    )
                    self.assertNotIn(
                        "refs/heads/",
                        guard,
                        f"{path.name}:{name} publishes on a branch push too",
                    )
                checked += 1

        self.assertGreater(checked, 0, "no publishing job was found to check")

    def test_every_stream_is_its_own_pipeline(self):
        jobs = self._ci()["jobs"]
        called = {
            job.get("with", {}).get("stream")
            for job in jobs.values()
            if str(job.get("uses", "")).endswith("build-runtime.yml")
        }
        self.assertEqual(called, {c.stream for c in m.all_configurations()})

    def test_a_provider_release_is_named_what_its_package_asks_for(self):
        # The build hook derives the tag from the package version. If the
        # release is named anything else the package cannot install, and
        # nothing else notices: the build is green and the release exists.
        import release_identity

        for provider in ep_matrix.PROVIDERS:
            package = REPO_ROOT / "packages" / f"onnxruntime_ep_{provider.name}_binaries"
            if not package.is_dir():
                continue

            declared = re.search(
                r"^version:\s*(\S+)",
                (package / "pubspec.yaml").read_text(encoding="utf-8"),
                re.M,
            )
            self.assertIsNotNone(declared, provider.name)

            expected = f"ep-{provider.name}-v{declared.group(1)}"
            self.assertEqual(
                provider.release_tag,
                expected,
                f"{provider.name}: the matrix and the package disagree",
            )

            # And what actually names the release. Every provider, however it
            # is obtained: a mirrored one has no plugin-ep directory in the
            # submodule, and reading one would fall back to the runtime version
            # without saying so.
            self.assertEqual(
                release_identity.provider_version(f"ep-{provider.name}"),
                declared.group(1),
                f"{provider.name}: the release would be named for a different "
                f"version than the package asks for",
            )

    def test_the_runtime_is_not_named_after_a_plugin(self):
        import release_identity

        self.assertIsNone(release_identity.provider_version("runtime"))

    def test_every_provider_that_is_published_has_a_package(self):
        # A provider we build or mirror with no package is a release nothing
        # installs. TensorRT is deliberately not here: it has no plugin-shaped
        # artifact upstream, which test_a_provider_without_a_package_is_safe
        # covers.
        for provider in ep_matrix.PROVIDERS:
            package = REPO_ROOT / "packages" / f"onnxruntime_ep_{provider.name}_binaries"
            self.assertTrue(
                package.is_dir(), f"{provider.name} is published with no package"
            )
            self.assertTrue((package / "hook" / "build.dart").is_file())

    def test_the_extensions_release_is_published(self):
        import yaml

        workflow = yaml.safe_load(
            (
                REPO_ROOT / ".github" / "workflows" / "build-extensions.yml"
            ).read_text(encoding="utf-8")
        )
        self.assertIn("release", workflow["jobs"])

    def test_every_mirrored_provider_has_a_workflow_and_a_job(self):
        jobs = self._ci()["jobs"]
        for provider in ep_matrix.fetched():
            workflow = (
                REPO_ROOT / ".github" / "workflows" / f"build-ep-{provider.name}.yml"
            )
            self.assertTrue(workflow.is_file(), workflow.name)
            self.assertTrue(
                any(
                    str(job.get("uses", "")).endswith(workflow.name)
                    for job in jobs.values()
                ),
                f"nothing in ci calls {workflow.name}",
            )

    def test_a_provider_never_gates_a_runtime(self):
        jobs = self._ci()["jobs"]
        providers = {
            name
            for name, job in jobs.items()
            if job.get("with", {}).get("stream") not in (None, "base", "full")
            or "build-ep-" in str(job.get("uses", ""))
        }
        for name, job in jobs.items():
            if job.get("with", {}).get("stream") in ("base", "full"):
                needs = job.get("needs", [])
                needs = [needs] if isinstance(needs, str) else needs
                self.assertFalse(
                    providers.intersection(needs),
                    f"{name} waits on a provider",
                )


class ReleaseAssetNames(unittest.TestCase):
    """That what we publish is what the jobs fetching it ask for.

    The names differ on purpose: a build produces `linux-x64-full` and the
    release carries `full-linux-x64`, because a release is a flat list where
    the component has to come first to be legible. Two places knowing that rule
    is what went wrong before, so the publisher owns it and everything else
    asks. These tests hold that line.
    """

    def _targets(self) -> list[tuple[str, str]]:
        """Every (local archive name, component) we ever publish."""
        pairs = [(config.id, "runtime") for config in m.CONFIGURATIONS]
        pairs += [(f"{config.id}-full", "runtime") for config in m.CONFIGURATIONS]
        return pairs

    def test_every_archive_gets_a_published_name(self):
        # None means "leave it alone", which for a real target would publish
        # the build's own name and 404 the hook that asks for the other one.
        for local, component in self._targets():
            with self.subTest(local=local):
                self.assertIsNotNone(
                    rename_release_assets.renamed(f"{local}.tar.gz", component),
                    f"{local} would be published under the build's own name",
                )

    def test_published_names_are_unique(self):
        seen: dict[str, str] = {}
        for local, component in self._targets():
            name = rename_release_assets.renamed(f"{local}.tar.gz", component)
            self.assertNotIn(
                name, seen, f"{local} and {seen.get(name)} both publish as {name}"
            )
            seen[name] = local

    def test_base_and_full_stay_distinct(self):
        # They differ by a suffix on one side and a prefix on the other, which
        # is exactly the kind of rule that collapses under a careless edit.
        for config in m.CONFIGURATIONS:
            base = rename_release_assets.renamed(f"{config.id}.tar.gz", "runtime")
            full = rename_release_assets.renamed(f"{config.id}-full.tar.gz", "runtime")
            self.assertEqual(base, f"base-{config.id}.tar.gz")
            self.assertEqual(full, f"full-{config.id}.tar.gz")

    def test_nothing_spells_a_release_asset_out_by_hand(self):
        """A job fetching from a release must derive the name, not type it.

        Typing it is how the full-runtime job came to ask a release that
        publishes `full-linux-x64` for `linux-x64-full`, which fails only when
        that one job runs against a release.
        """
        text = (REPO_ROOT / ".github" / "workflows" / "ci.yml").read_text(
            encoding="utf-8"
        )
        for line in text.splitlines():
            if "--pattern" not in line or "$asset" in line:
                continue
            # The provider jobs match a family rather than one archive, which
            # is a glob and not a name that can drift.
            self.assertIn(
                "*",
                line,
                f"{line.strip()} names a release asset outright; ask "
                f"rename_release_assets.py --name for it instead",
            )


class ArtifactArchitecture(unittest.TestCase):
    """That packaging checks what it ships without refusing what it should.

    The check exists because a path is not evidence of an architecture, which
    is how an ARM64EC shader compiler came to be shipped as ARM64. It runs on
    every file that goes into a release archive, so it has to be right about
    the targets that have no machine code as well as the ones that do.
    """

    def test_a_wasm_artifact_passes_for_every_target(self):
        # Nothing in a web build claims an architecture, so asking the table
        # what wasm32 means before reading the file would refuse to package
        # the web builds at all.
        with tempfile.TemporaryDirectory() as tmp:
            wasm = pathlib.Path(tmp) / "onnxruntime.wasm"
            wasm.write_bytes(b"\x00asm\x01\x00\x00\x00" + b"\x00" * 256)
            for arch in sorted({config.arch for config in m.CONFIGURATIONS}):
                with self.subTest(arch=arch):
                    binary_arch.verify(wasm, arch)

    def test_machine_code_for_an_unknown_target_is_refused(self):
        with tempfile.TemporaryDirectory() as tmp:
            elf = pathlib.Path(tmp) / "libonnxruntime.so"
            # An ELF header claiming aarch64, which is all the check reads.
            header = bytearray(b"\x7fELF\x02\x01\x01" + b"\x00" * 121)
            header[0x12] = 0xB7
            elf.write_bytes(bytes(header))
            binary_arch.verify(elf, "arm64")
            with self.assertRaises(SystemExit):
                binary_arch.verify(elf, "x86_64")

    def test_every_extensions_target_has_a_known_architecture(self):
        # Extensions package themselves, in build_extensions.py, rather than
        # through package_artifact.py. That is how they came to ship for
        # thirteen targets with neither check on them, so their architectures
        # have to stay readable here too.
        import extensions_matrix

        for build in extensions_matrix.BUILDS:
            with self.subTest(build=build.id):
                self.assertIn(
                    build.arch,
                    binary_arch.TARGETS,
                    f"{build.id} builds for {build.arch}, which packaging "
                    f"cannot check",
                )

    def test_every_native_target_has_a_known_architecture(self):
        for config in m.CONFIGURATIONS:
            if config.arch == "wasm32":
                continue
            with self.subTest(config=config.id):
                self.assertIn(
                    config.arch,
                    binary_arch.TARGETS,
                    f"{config.id} builds for {config.arch}, which packaging "
                    f"cannot check",
                )


    def test_an_android_library_may_only_need_what_android_has(self):
        """The compensating control for a platform nothing can run.

        arm64 Android cannot be executed anywhere in CI, so a dependency that
        resolves on the build machine and not on a phone would reach a user
        before it reached us. libc++_shared is the one that gets linked by
        accident.
        """
        with tempfile.TemporaryDirectory() as tmp:
            path = pathlib.Path(tmp) / "libonnxruntime.so"
            # Nothing readable means nothing to object to. A truncated file
            # in particular must not raise: packaging would then report a
            # struct error rather than whatever the real problem was.
            for blob in (
                b"not an elf",
                b"",
                b"\x7fELF\x02\x01\x01" + b"\x00" * 40,
                b"\x7fELF\x02\x01\x01" + b"\x00" * 200,
            ):
                path.write_bytes(blob)
                self.assertEqual(binary_arch.dependencies(path), [])
                binary_arch.verify_android_dependencies(path)
                binary_arch.verify(path, "arm64-v8a")

        self.assertIn("libc.so", binary_arch.ANDROID_PROVIDED)
        self.assertNotIn("libc++_shared.so", binary_arch.ANDROID_PROVIDED)


class PackagingRunsItsChecks(unittest.TestCase):
    """That packaging really runs its checks, on every configuration.

    The checks themselves are unit tested above. This exercises them where
    they are wired in, because that is the part CI would otherwise never see:
    the build jobs skip packaging on an artifact cache hit, so the step only
    runs when the runtime source or its flags change.
    """

    @staticmethod
    def _header(arch: str) -> bytes:
        if arch == "wasm32":
            return b"\x00asm\x01\x00\x00\x00" + b"\x00" * 256
        machine = {
            "arm64": 0xB7, "arm64-v8a": 0xB7, "aarch64": 0xB7,
            "armeabi-v7a": 0x28, "x86": 0x03,
        }.get(arch, 0x3E)
        header = bytearray(b"\x7fELF\x02\x01\x01" + b"\x00" * 121)
        header[0x12] = machine
        return bytes(header)

    def _tree(self, root: pathlib.Path, config) -> bool:
        """Lays out what a build of [config] would leave behind."""
        import package_artifact

        members = package_artifact.ARTIFACT_PATTERNS.get(config.platform, {}).get(
            config.component
        )
        if not members:
            return False
        build = root / "build" / config.id / "Release"
        build.mkdir(parents=True, exist_ok=True)
        for canonical, patterns in members.items():
            name = (
                patterns[0].replace("*", "x") if canonical == "*" else canonical
            )
            (build / name).write_bytes(self._header(config.arch))
        return True

    def test_every_configuration_packages(self):
        import package_artifact

        root = pathlib.Path(tempfile.mkdtemp())
        original = package_artifact.REPO_ROOT, package_artifact.DIST
        package_artifact.REPO_ROOT = root
        package_artifact.DIST = root / "dist"
        try:
            packaged = 0
            for config in m.CONFIGURATIONS:
                if not self._tree(root, config):
                    continue
                with self.subTest(config=config.id):
                    package_artifact.package(config)
                    packaged += 1
            self.assertGreater(packaged, 0, "nothing was packaged to check")
        finally:
            package_artifact.REPO_ROOT, package_artifact.DIST = original

    def test_a_wrong_architecture_is_refused(self):
        import package_artifact

        config = next(
            c for c in m.CONFIGURATIONS if c.arch == "arm64-v8a"
        )
        root = pathlib.Path(tempfile.mkdtemp())
        original = package_artifact.REPO_ROOT, package_artifact.DIST
        package_artifact.REPO_ROOT = root
        package_artifact.DIST = root / "dist"
        try:
            self._tree(root, config)
            # Same names, x86-64 inside. This is the mistake the check exists
            # for, and it has to fail the build rather than ship.
            build = root / "build" / config.id / "Release"
            for f in build.iterdir():
                f.write_bytes(self._header("x86_64"))
            with self.assertRaises(SystemExit):
                package_artifact.package(config)
        finally:
            package_artifact.REPO_ROOT, package_artifact.DIST = original


class ApiAndBinariesAreSeparate(unittest.TestCase):
    """A Dart API and the library it drives are versioned apart.

    Every package that offers an API and also ships a binary is two packages:
    the API, on a version of its own, and `<name>_binaries` on the binary's.
    That is what lets an application move one without the other, and take the
    API with no binary at all when it means to supply the library itself.

    The pairing is not enforced by pub, which is why it is enforced here.
    """

    def _pubspec(self, package: str) -> str:
        return (REPO_ROOT / "packages" / package / "pubspec.yaml").read_text(
            encoding="utf-8"
        )

    def _api_packages(self) -> list[str]:
        """Packages whose Dart names an asset in a sibling binaries package."""
        found = []
        for package in sorted((REPO_ROOT / "packages").iterdir()):
            if not package.is_dir() or package.name.endswith("_binaries"):
                continue
            for dart in package.glob("lib/**/*.dart"):
                if f"package:{package.name}_binaries/" in dart.read_text(
                    encoding="utf-8"
                ):
                    found.append(package.name)
                    break
        return found

    def test_each_api_package_has_a_binaries_package(self):
        packages = self._api_packages()
        self.assertGreater(len(packages), 0, "no API package was found to check")
        for name in packages:
            with self.subTest(package=name):
                self.assertTrue(
                    (REPO_ROOT / "packages" / f"{name}_binaries").is_dir(),
                    f"{name} names an asset in {name}_binaries, which does not "
                    f"exist",
                )

    def test_an_api_package_runs_no_hook(self):
        # The hook installs the binary, so it belongs to the package that is
        # the binary. An API package with a hook would install one whether the
        # application wanted it or not.
        for name in self._api_packages():
            with self.subTest(package=name):
                self.assertFalse(
                    (REPO_ROOT / "packages" / name / "hook").exists(),
                    f"{name} has a hook, which belongs in {name}_binaries",
                )

    def test_an_api_package_does_not_require_its_binaries(self):
        """The binary stays optional, which is the point of the split.

        Naming it as a real dependency would make every application take our
        build of it, and there would be no way to supply one at run time
        instead. A dev dependency is fine and is how these packages test
        themselves: dev dependencies are not transitive, so nothing an
        application depends on is affected by one.
        """
        import yaml

        for name in self._api_packages():
            with self.subTest(package=name):
                spec = yaml.safe_load(self._pubspec(name))
                self.assertNotIn(
                    f"{name}_binaries",
                    spec.get("dependencies") or {},
                    f"{name} requires {name}_binaries, so an application "
                    f"cannot supply its own library",
                )

    def test_an_api_version_names_the_binary_it_was_written_against(self):
        for name in self._api_packages():
            with self.subTest(package=name):
                version = re.search(
                    r"^version:\s*(\S+)\s*$", self._pubspec(name), re.MULTILINE
                ).group(1)
                self.assertIn(
                    "+",
                    version,
                    f"{name} is {version}, which names no binary. Use "
                    f"<own version>+<component>-<binary version>.",
                )


if __name__ == "__main__":
    unittest.main(verbosity=2)

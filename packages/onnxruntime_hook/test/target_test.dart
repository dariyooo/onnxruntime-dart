@TestOn('vm')

/// The build hook maps a target to a release asset. A wrong mapping downloads a
/// library for the wrong architecture, which fails at load time on a user's
/// device rather than during our build.
library;

import 'package:code_assets/code_assets.dart';
import 'package:onnxruntime_hook/onnxruntime_hook.dart';
import 'package:test/test.dart';

void main() {
  _librarySiblingTests();
  _simulatorAdviceTests();
  _companionTests();
  group('targetId', () {
    const cases = <(OS, Architecture, IOSSdk?), String>{
      (OS.android, Architecture.arm64, null): 'android-arm64-v8a',
      (OS.android, Architecture.arm, null): 'android-armeabi-v7a',
      (OS.android, Architecture.x64, null): 'android-x86_64',
      (OS.android, Architecture.ia32, null): 'android-x86',
      (OS.linux, Architecture.x64, null): 'linux-x64',
      (OS.linux, Architecture.arm64, null): 'linux-arm64',
      (OS.macOS, Architecture.arm64, null): 'macos-arm64',
      (OS.macOS, Architecture.x64, null): 'macos-x86_64',
      (OS.windows, Architecture.x64, null): 'windows-x64',
      (OS.windows, Architecture.arm64, null): 'windows-arm64',
      (OS.iOS, Architecture.arm64, IOSSdk.iPhoneOS): 'ios-device-arm64',
      (OS.iOS, Architecture.arm64, IOSSdk.iPhoneSimulator): 'ios-sim-arm64',
      (OS.iOS, Architecture.x64, null): 'ios-sim-x86_64',
    };

    cases.forEach((target, expected) {
      final (os, architecture, sdk) = target;
      test('$os $architecture${sdk == null ? '' : ' $sdk'} -> $expected', () {
        expect(
          targetId(os: os, architecture: architecture, iosSdk: sdk),
          expected,
        );
      });
    });

    test('covers every published target exactly once', () {
      expect(cases.values.toSet(), supportedTargets.toSet());
      expect(cases.values.length, cases.values.toSet().length);
    });

    test('device and simulator differ on the same architecture', () {
      // They are separate artifacts, so conflating them ships a library that
      // cannot load.
      expect(
        targetId(
          os: OS.iOS,
          architecture: Architecture.arm64,
          iosSdk: IOSSdk.iPhoneOS,
        ),
        isNot(
          targetId(
            os: OS.iOS,
            architecture: Architecture.arm64,
            iosSdk: IOSSdk.iPhoneSimulator,
          ),
        ),
      );
    });

    test('refuses iOS arm64 without an SDK rather than guessing', () {
      expect(
        () => targetId(os: OS.iOS, architecture: Architecture.arm64),
        throwsA(isA<UnsupportedTarget>()),
      );
    });

    test('refuses architectures we publish nothing for', () {
      expect(
        () => targetId(os: OS.linux, architecture: Architecture.riscv64),
        throwsA(
          isA<UnsupportedTarget>().having(
            (e) => e.toString(),
            'message',
            contains('Supported targets'),
          ),
        ),
      );
    });
  });

  group('artifact naming', () {
    test('library name follows platform convention', () {
      expect(libraryFileName(OS.windows), 'onnxruntime.dll');
      expect(libraryFileName(OS.macOS), 'libonnxruntime.dylib');
      expect(libraryFileName(OS.iOS), 'libonnxruntime.dylib');
      expect(libraryFileName(OS.linux), 'libonnxruntime.so');
      expect(libraryFileName(OS.android), 'libonnxruntime.so');
    });

    test('every component names its asset the same way', () {
      // Component first, target second. The runtime used to be the exception,
      // named for the target alone with the variant appended, which read fine
      // and sorted badly beside everything else.
      expect(assetFileName('linux-x64'), 'base-linux-x64.tar.gz');
      expect(assetFileName('linux-x64-full'), 'full-linux-x64.tar.gz');
      expect(
        providerAssetFileName('webgpu', 'linux-x64'),
        'webgpu-linux-x64.tar.gz',
      );
      expect(
        extensionsAssetFileName('linux-x64'),
        'extensions-linux-x64.tar.gz',
      );
    });

    test('asset url points at the pinned release', () {
      final url = assetUrl(
        releaseTag: 'runtime-v1.29.0',
        targetId: 'linux-x64',
      );
      expect(
          url.toString(), endsWith('/runtime-v1.29.0/base-linux-x64.tar.gz'));
      expect(url.scheme, 'https');
    });

    group('release tag from a package version', () {
      test('a plain version names the release directly', () {
        expect(releaseTagFor('1.29.0'), 'runtime-v1.29.0');
      });

      test('a repackaged version still points at the upstream release', () {
        // The reason this exists. `1.29.0+1` is the same ONNX Runtime built
        // once and packaged twice, so there is no `runtime-v1.29.0+1` release
        // to download and asking for one would 404 every install.
        expect(releaseTagFor('1.29.0+1'), 'runtime-v1.29.0');
        expect(releaseTagFor('1.29.0+17'), 'runtime-v1.29.0');
      });

      test('each component names its own release', () {
        expect(releaseTagFor('0.15.2+1', component: 'genai'), 'genai-v0.15.2');
        expect(
          releaseTagFor('0.3.0+2', component: 'ep-webgpu'),
          'ep-webgpu-v0.3.0',
        );
      });
    });
  });

  group('variants', () {
    test('base is the default and adds no suffix', () {
      expect(
        targetId(os: OS.linux, architecture: Architecture.x64),
        'linux-x64',
      );
    });

    test('full names a different asset', () {
      // A different library, so it must not resolve to the base one.
      expect(
        targetId(
          os: OS.linux,
          architecture: Architecture.x64,
          variant: OrtVariant.full,
        ),
        'linux-x64-full',
      );
    });

    test('every supported target has both variants', () {
      for (final base in supportedTargets) {
        expect('$base${OrtVariant.base.suffix}', base);
        expect('$base${OrtVariant.full.suffix}', '$base-full');
      }
    });

    test('an unknown variant is refused, listing the real ones', () {
      expect(
        () => OrtVariant.byName('everything'),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.toString(),
            'message',
            allOf(contains('base'), contains('full')),
          ),
        ),
      );
    });

    test('names match what the build matrix produces', () {
      // ort_matrix.py appends "-full" to build the full configuration id.
      expect(OrtVariant.base.suffix, '');
      expect(OrtVariant.full.suffix, '-full');
    });
  });
}

void _companionTests() {
  group('GenAI companion libraries', () {
    test('android needs libmat.so beside the library', () {
      // Regression: the APK bundled only libonnxruntime-genai.so, and the
      // device tests failed with `dlopen failed: library "libmat.so" not
      // found`. A DT_NEEDED entry is not something the bundler follows.
      expect(OrtGenAi.companions(OS.android), ['libmat.so']);
    });

    test('nothing else needs one', () {
      for (final os in [OS.linux, OS.macOS, OS.windows, OS.iOS]) {
        expect(OrtGenAi.companions(os), isEmpty, reason: '$os');
      }
    });
  });
}

void _simulatorAdviceTests() {
  group('the unsupported-target message', () {
    test('ios-sim-x86_64 is a real case a user hits, not just CI', () {
      // Found by CI: `flutter build ios --simulator` with no device compiles
      // for arm64 and x86_64 together, so the hooks are asked for a target
      // upstream does not publish. Anyone building our package for the
      // simulator the same way hits it, so the message has to say what to do.
      expect(OrtGenAi.isAvailableOn('ios-sim-x86_64'), isFalse);
      expect(OrtGenAi.isAvailableOn('ios-sim-arm64'), isTrue);
    });
  });
}

void _librarySiblingTests() {
  group('library detection for provider siblings', () {
    test('recognises every shared library extension we ship', () {
      // QNN's archive is the reason this exists: the provider dlopens eleven
      // Qualcomm libraries by name, and the set differs per target, so they
      // are matched by extension rather than by a list that would silently
      // drop whichever target was not listed.
      for (final name in [
        'libQnnHtp.so',
        'libc++-71bc274c.so.1.0',
        'QnnHtp.dll',
        'libonnxruntime-genai.dylib',
      ]) {
        expect(isLibraryFileName(name), isTrue, reason: name);
      }
    });

    test('does not mistake the licence files that travel with them', () {
      for (final name in [
        'LICENSE',
        'Privacy.md',
        'Qualcomm_LICENSE.pdf',
        'ThirdPartyNotices.txt',
      ]) {
        expect(isLibraryFileName(name), isFalse, reason: name);
      }
    });
  });
}

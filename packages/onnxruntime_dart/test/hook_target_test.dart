@TestOn('vm')

/// The build hook maps a target to a release asset. A wrong mapping downloads a
/// library for the wrong architecture, which fails at load time on a user's
/// device rather than during our build.
library;

import 'package:code_assets/code_assets.dart';
import 'package:onnxruntime_dart/src/hook/target.dart';
import 'package:test/test.dart';

void main() {
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

    test('asset url points at the pinned release', () {
      final url = assetUrl(
        releaseTag: 'runtime-v1.29.0+1',
        targetId: 'linux-x64',
      );
      expect(url.toString(), endsWith('/runtime-v1.29.0+1/linux-x64.tar.gz'));
      expect(url.scheme, 'https');
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

@TestOn('vm')

/// The providers the EP package can install.
///
/// Selection happens at build time from a list in `user_defines`, so a mistake
/// here is a download that never happens or a library that cannot exist for the
/// target. Both are cheaper to catch as a test than as a build failure.
library;

import 'package:code_assets/code_assets.dart';
import 'package:onnxruntime_hook/onnxruntime_hook.dart';
import 'package:test/test.dart';

void main() {
  group('provider availability', () {
    test('every provider is published for at least one target', () {
      for (final provider in OrtProvider.values) {
        expect(provider.targets, isNotEmpty, reason: provider.name);
      }
    });

    test('every target named is one we actually build for', () {
      for (final provider in OrtProvider.values) {
        for (final target in provider.targets) {
          expect(
            supportedTargets,
            contains(target),
            reason: '${provider.name} claims $target, which is not a target',
          );
        }
      }
    });

    test('CUDA is desktop only', () {
      // No macOS, Android or iOS build exists, and asking for one should be
      // refused rather than silently skipped.
      expect(OrtProvider.cuda.isAvailableOn('linux-x64'), isTrue);
      expect(OrtProvider.cuda.isAvailableOn('windows-x64'), isTrue);
      expect(OrtProvider.cuda.isAvailableOn('android-arm64-v8a'), isFalse);
      expect(OrtProvider.cuda.isAvailableOn('macos-arm64'), isFalse);
      expect(OrtProvider.cuda.isAvailableOn('ios-device-arm64'), isFalse);
    });

    test('QNN is where Qualcomm hardware is', () {
      expect(OrtProvider.qnn.isAvailableOn('android-arm64-v8a'), isTrue);
      expect(OrtProvider.qnn.isAvailableOn('linux-x64'), isFalse);
    });
  });

  group('library names', () {
    test('follow each platform, and match what the runtime looks for', () {
      // ONNX Runtime resolves a relative name against its own directory, so
      // the name has to be exactly what it expects to find there.
      expect(
        OrtProvider.webgpu.libraryFileName(OS.linux),
        'libonnxruntime_providers_webgpu.so',
      );
      expect(
        OrtProvider.webgpu.libraryFileName(OS.windows),
        'onnxruntime_providers_webgpu.dll',
      );
      expect(
        OrtProvider.webgpu.libraryFileName(OS.macOS),
        'libonnxruntime_providers_webgpu.dylib',
      );
    });

    test('an unknown provider names the ones that exist', () {
      expect(
        () => OrtProvider.byName('nope'),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            allOf(contains('cuda'), contains('webgpu')),
          ),
        ),
      );
    });
  });
}

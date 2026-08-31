@TestOn('vm')
@Tags(['exclusive'])

/// Finding execution provider libraries.
///
/// A provider plugin is opened by ONNX Runtime from a path, which does not fit
/// how code assets work: they are bundled to be linked against, and Dart never
/// says where they landed. There is no API for it and there will not be one,
/// so two mechanisms carry this instead, and both are checked here.
library;

import 'dart:ffi';

import 'package:onnxruntime_dart/native.dart';
import 'package:onnxruntime_dart/onnxruntime_dart.dart';
import 'package:test/test.dart';

import 'src/ort_library.dart';
import 'src/test_models.dart';

void main() {
  group('recovering a library path from the loader', () {
    test('finds the file an address came from', () {
      // The runtime is loaded as a code asset, so nothing knows its path. The
      // operating system does: any address inside it identifies the file.
      final inside = ortApi().ref.GetTrainingApi.cast<Void>();
      final path = libraryPathOf(inside);

      expect(path, isNotNull);
      expect(path, contains('onnxruntime'));
    });

    test('the path names a real library, wherever it was bundled', () {
      final path = libraryPathOf(ortApi().ref.GetTrainingApi.cast<Void>())!;
      final fileName = path.split(RegExp(r'[/\\]')).last;

      // Existence is deliberately not asserted. On Android the loader reports
      // paths inside the APK, such as base.apk!/lib/arm64-v8a/libfoo.so, which
      // dlopen accepts and File.existsSync does not.
      expect(
        fileName,
        anyOf(
          contains('.so'),
          contains('.dylib'),
          contains('.dll'),
          contains('onnxruntime'),
        ),
        reason: '$path does not look like a library',
      );
    });

    test('an address outside any library reports nothing', () {
      expect(libraryPathOf(Pointer<Void>.fromAddress(1)), isNull);
    });
  }, skip: skipWithoutOrt ?? skipWithoutNativeAsset);

  group('providers that were not installed', () {
    test('report no path rather than another library\'s', () {
      // Every plugin exports the same entry point, so a provider that is not
      // installed resolves to whatever else in the process exports it. Without
      // the file-name check that would be reported as a real path, and the
      // runtime would be handed the wrong library.
      for (final provider in OrtExecutionProvider.values) {
        final path = bundledProviderPath(provider);
        if (path == null) continue;
        expect(
          path.split(RegExp(r'[/\\]')).last,
          contains(provider.libraryStem),
          reason: '${provider.name} resolved to $path, which is not it',
        );
      }
    });

    test('none are installed in this workspace, so none register', () {
      // onnxruntime_ep is not a dependency of the test suite. If this starts
      // failing, a provider is being installed and the test should say so.
      expect(registerBundledProviders(), isEmpty);
    });
  }, skip: skipWithoutOrt ?? skipWithoutNativeAsset);

  group('bringing your own library', () {
    test('a custom operator library is refused when it is not one', () {
      // Nothing about a custom ops library is specific to this package: it is
      // a shared library exporting RegisterCustomOps, and anyone can build
      // one. What is checked here is that the path reaches ONNX Runtime and
      // that a library without the entry point is reported rather than
      // silently ignored.
      final runtime = libraryPathOf(ortApi().ref.GetTrainingApi.cast<Void>())!;

      expect(
        () => Session.fromBytes(
          voiceCommands.model(),
          options: SessionOptions(customOpsLibraries: [runtime]),
        ),
        throwsA(isA<OrtException>()),
      );
    });

    test('a model loads normally when none are given', () {
      final session = Session.fromBytes(voiceCommands.model());
      addTearDown(session.release);
      expect(session.inputs, hasLength(1));
    });
  }, skip: skipWithoutOrt ?? skipWithoutNativeAsset);

  group('the provider table', () {
    test('every provider names a library and where it is published', () {
      for (final provider in OrtExecutionProvider.values) {
        expect(provider.libraryStem, startsWith('onnxruntime_providers_'));
        expect(provider.registrationName, isNotEmpty);
      }
    });

    test('registration names are distinct', () {
      final names =
          OrtExecutionProvider.values.map((p) => p.registrationName).toSet();
      expect(names, hasLength(OrtExecutionProvider.values.length));
    });
  });
}

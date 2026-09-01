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
import 'dart:io';

import 'package:onnxruntime_dart/native.dart';
import 'package:onnxruntime_dart/onnxruntime_dart.dart';
import 'package:test/test.dart';

import 'src/ort_library.dart';
import 'src/paths.dart';
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

  group('a library that was not installed', () {
    test('reports nothing rather than another library\'s path', () {
      // The check that makes the whole scheme safe. A code asset that is not
      // installed falls back to a process-wide symbol lookup, and every
      // provider exports the same entry point, so without comparing the file
      // name one library's path gets reported for another.
      final wrong = loadedLibraryPath(
        () => ortApi().cast<Void>(),
        stem: 'a_library_that_does_not_exist',
      );
      expect(wrong, isNull);
    });

    test('reports the path when the name does match', () {
      // The same lookup against the runtime itself, which is loaded, so the
      // negative result above is the check working rather than the lookup
      // being broken in general.
      final found = loadedLibraryPath(
        () => ortApi().cast<Void>(),
        stem: 'onnxruntime',
      );
      expect(found, isNotNull);
      expect(found, contains('onnxruntime'));
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

  test('this package knows about no provider in particular', () {
    // The point of the split. A provider package declares its own asset and
    // finds it with loadedLibraryPath; nothing here names one, so adding a
    // provider is a new package rather than an edit to this one.
    final sources = Directory('${fromPackage('lib')}/src')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));

    for (final file in sources) {
      expect(
        file.readAsStringSync(),
        isNot(contains('package:onnxruntime_ep_')),
        reason: '${file.path} names a provider package, which inverts the '
            'dependency: the base must not know its own dependents',
      );
    }
  });
}

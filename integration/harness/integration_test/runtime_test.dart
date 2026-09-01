// Runs on a real Android device and a real iOS device.
//
// Everything else in this repository is tested by `dart test`, which cannot run
// on either: there is no Dart SDK for them, `dart compile exe` rejects those
// targets, and package:test has no mobile platform. Flutter's integration_test
// is the only way to execute Dart on a phone, so this is where the mobile
// claims are checked rather than assumed.
//
// Two of those claims matter most, and both are about where a bundled library
// ends up. Android maps libraries out of the APK rather than unpacking them,
// so a path can name something inside a zip. iOS repackages each one into a
// code-signed framework. Neither resembles the desktop layout, and the whole
// execution provider design rests on being able to recover a path there.

import 'dart:ffi';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:onnxruntime_dart/native.dart';
import 'package:onnxruntime_dart/onnxruntime_dart.dart' hide runtimeVersion;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('the runtime loads at all', () {
    test('reports its version', () {
      // The build hook bundled a library and Flutter placed it somewhere only
      // it knows. If this works, the whole native asset path works here.
      expect(runtimeVersion(), matches(RegExp(r'^\d+\.\d+\.\d+')));
    });

    test('the API version matches the bindings', () {
      expect(ortApi(), isNot(equals(0)));
      expect(ORT_API_VERSION, 29);
    });

    test('reports whether training was compiled in', () {
      expect(trainingIsAvailable(), isA<bool>());
    });
  });

  group('finding a library on this platform', () {
    test('the loader knows where the runtime came from', () {
      // The claim under test. On Android this is expected to be a path inside
      // the APK, such as base.apk!/lib/arm64-v8a/libonnxruntime.so, and on iOS
      // a path inside a framework in the app bundle.
      final path = libraryPathOf(ortApi().ref.GetTrainingApi.cast<Void>());

      expect(path, isNotNull, reason: 'dladdr found nothing on this platform');
      expect(path, contains('onnxruntime'));
      // Printed rather than asserted: the shape is what we are here to learn.
      // ignore: avoid_print
      print('runtime library path: $path');
    });

    test('an address in no library reports nothing', () {
      expect(libraryPathOf(Pointer<Void>.fromAddress(1)), isNull);
    });

    test('a library that is not installed reports nothing on device', () {
      // The check that makes the scheme safe, exercised where it is hardest:
      // Android maps libraries out of the APK and iOS repackages each into its
      // own framework, so the loader reports paths that look nothing like a
      // desktop layout. A name that is not there must still come back null
      // rather than resolving to the runtime.
      expect(
        loadedLibraryPath(
          () => ortApi().cast<Void>(),
          stem: 'a_library_that_does_not_exist',
        ),
        isNull,
      );
    });

    test('a library that is installed is found on device', () {
      // The same lookup against the runtime itself, which proves the negative
      // above is the name check working rather than the lookup failing here.
      expect(
        loadedLibraryPath(() => ortApi().cast<Void>(), stem: 'onnxruntime'),
        isNotNull,
      );
    });
  });

  group('running a model', () {
    late Uint8List model;

    setUpAll(() async {
      model = (await rootBundle.load('assets/model.onnx')).buffer.asUint8List();
    });

    test('loads and reports its signature', () {
      final session = Session.fromBytes(model);
      addTearDown(session.release);

      expect(session.inputs.single.name, 'input_1');
      expect(session.inputs.single.shape, [1, 6]);
      expect(session.outputs.single.shape, [1, 26]);
    });

    test('runs and produces the right shape', () {
      final session = Session.fromBytes(model);
      addTearDown(session.release);

      final input = OrtTensor.fromData(OrtElementType.float32, Float32List(6), [
        1,
        6,
      ]);
      addTearDown(input.release);

      final outputs = session.run({'input_1': input});
      addTearDown(() {
        for (final output in outputs.values) {
          output.release();
        }
      });

      expect(outputs['dense_1']!.view.float32s, hasLength(26));
    });

    test('runs without blocking the isolate', () async {
      final session = Session.fromBytes(
        model,
        options: const SessionOptions(intraOpNumThreads: 2),
      );
      addTearDown(session.release);

      final input = OrtTensor.fromData(OrtElementType.float32, Float32List(6), [
        1,
        6,
      ]);
      addTearDown(input.release);

      final outputs = await session.runAsync({'input_1': input});
      addTearDown(() {
        for (final output in outputs.values) {
          output.release();
        }
      });

      expect(outputs['dense_1']!.view.float32s, hasLength(26));
    });
  });
}

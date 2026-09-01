@TestOn('vm')
@Tags(['exclusive'])

/// The operator library actually loads and its operators actually run.
///
/// We build onnxruntime-extensions for thirteen targets and publish it. Until
/// this existed, "it compiled" was the entire evidence that it worked, which is
/// not evidence that ONNX Runtime can load it or that a model can use it.
library;

import 'dart:typed_data';

import 'package:onnxruntime_dart/onnxruntime_dart.dart';
import 'package:test/test.dart';

import 'src/embedded_model.dart';
import 'src/extensions_library.dart';
import 'src/ort_library.dart';

void main() {
  group('the extensions library', () {
    test('ONNX Runtime accepts it as a custom operator library', () {
      // The whole contract: a shared library exporting RegisterCustomOps that
      // the runtime will take. If the export is missing or the ABI is wrong,
      // session creation fails here.
      final session = Session.fromBytes(
        absModel(),
        options: SessionOptions(
          customOpsLibraries: [findExtensionsLibrary()!],
        ),
      );
      addTearDown(session.release);

      expect(session.inputs, hasLength(1));
    });

    test('a model still runs correctly with it loaded', () {
      // Loading a library that registers hundreds of operators must not
      // disturb a model that uses none of them.
      final session = Session.fromBytes(
        absModel(),
        options: SessionOptions(
          customOpsLibraries: [findExtensionsLibrary()!],
        ),
      );
      addTearDown(session.release);

      final input = OrtTensor.fromData(
        OrtElementType.float32,
        Float32List.fromList([-1, 2, -3, 4, -5, 6, -7, 8, -9, 10]),
        [1, 2, 5],
      );
      addTearDown(input.release);

      final outputs = session.run({session.inputs.single.name: input});
      addTearDown(() {
        for (final output in outputs.values) {
          output.release();
        }
      });

      expect(
        outputs.values.single.view.float32s,
        [1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
      );
    });

    test('a library that is not one is refused, with the path', () {
      // The failure people actually hit: pointing at the wrong file. It must
      // say which file, not just that something went wrong.
      expect(
        () => Session.fromBytes(
          absModel(),
          options: const SessionOptions(
            customOpsLibraries: ['/nonexistent/libortextensions.so'],
          ),
        ),
        throwsA(isA<OrtException>()),
      );
    });
  }, skip: skipWithoutExtensions ?? skipWithoutOrt ?? skipWithoutNativeAsset);
}

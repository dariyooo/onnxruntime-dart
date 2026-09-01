@Tags(['exclusive'])

/// The contract, on whichever platform this is.
///
/// Deliberately not `@TestOn('vm')`. Everything here goes through the public
/// API and the backend seam, so it is the same code on both platforms and the
/// same test should prove it on both. What differs is only whether a runtime is
/// available, which `skipWithoutRuntime` answers per platform.
///
/// Tests that read the model corpus stay native: the corpus lives in the
/// submodule and is read with `dart:io`. One model is embedded here instead, so
/// the shared suite needs no filesystem.
library;

import 'dart:typed_data';

import 'package:onnxruntime_dart/onnxruntime_dart.dart';
import 'package:test/test.dart';

import 'src/embedded_model.dart';
import 'src/runtime.dart';

void main() {
  setUpAll(ensureRuntime);

  group('the runtime', () {
    test('reports a version', () {
      expect(runtimeVersion(), matches(RegExp(r'^\d+\.\d+\.\d+')));
    });

    test('lists the providers it was built with', () {
      final providers = availableProviders();
      expect(providers, isNotEmpty);
      expect(providers, contains('CPUExecutionProvider'));
    });
  }, skip: skipWithoutRuntime);

  group('a session', () {
    late Session session;

    setUp(() => session = Session.fromBytes(absModel()));
    tearDown(() => session.release());

    test('reports what the model wants', () {
      expect(session.inputs, hasLength(1));
      expect(session.outputs, hasLength(1));
      expect(session.inputs.single.elementType, OrtElementType.float32);
    });

    test('reports a free dimension as one the model decides', () {
      // The model is declared [-1, -1, 5], so the first two are the caller's
      // choice and the last is not.
      expect(session.inputs.single.isDynamic, isTrue);
      expect(session.inputs.single.shape.last, 5);
    });

    test('runs and returns the right shape and values', () {
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

      final view = outputs.values.single.view;
      expect(view.shape, [1, 2, 5]);
      expect(view.float32s, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
    });

    test('accepts a different shape for a free dimension', () {
      // The point of a free dimension: one session, many batch sizes.
      for (final rows in [1, 3]) {
        final input = OrtTensor.fromData(
          OrtElementType.float32,
          Float32List(rows * 5)..fillRange(0, rows * 5, -2),
          [1, rows, 5],
        );
        final outputs = session.run({session.inputs.single.name: input});

        expect(outputs.values.single.view.shape, [1, rows, 5]);
        expect(
            outputs.values.single.view.float32s.every((v) => v == 2), isTrue);

        input.release();
        for (final output in outputs.values) {
          output.release();
        }
      }
    });

    test('refuses an input of the wrong rank rather than reading past it', () {
      final wrong = OrtTensor.fromData(
        OrtElementType.float32,
        Float32List.fromList([1, 2, 3]),
        [3],
      );
      addTearDown(wrong.release);

      expect(
        () => session.run({session.inputs.single.name: wrong}),
        throwsA(isA<OrtException>()),
      );
    });

    test('refuses an input the model does not have', () {
      final input = OrtTensor.fromData(
        OrtElementType.float32,
        Float32List(5),
        [1, 1, 5],
      );
      addTearDown(input.release);

      expect(
        () => session.run({'not_an_input': input}),
        throwsA(anything),
      );
    });
  }, skip: skipWithoutRuntime);

  group('handles', () {
    test('a released session refuses further use rather than crashing', () {
      final session = Session.fromBytes(absModel());
      final input = OrtTensor.fromData(
        OrtElementType.float32,
        Float32List(5),
        [1, 1, 5],
      );
      addTearDown(input.release);
      session.release();

      // Metadata was read when the session was built and is Dart-side, so it
      // survives. Anything that reaches the handle must not.
      expect(
        () => session.run({session.inputs.single.name: input}),
        throwsA(isA<StateError>()),
      );
    });

    test('releasing twice is refused, not ignored', () {
      final session = Session.fromBytes(absModel());
      session.release();

      expect(session.release, throwsA(isA<StateError>()));
    });

    test('a released tensor refuses further use', () {
      final tensor = OrtTensor.fromData(
        OrtElementType.float32,
        Float32List(5),
        [1, 1, 5],
      );
      tensor.release();

      expect(() => tensor.view, throwsA(isA<StateError>()));
    });
  }, skip: skipWithoutRuntime);

  group('tensors', () {
    test('round-trip float32 without mangling the bytes', () {
      // Values chosen to change if anything reorders bytes or narrows.
      final values = Float32List.fromList([
        0,
        -0.0,
        1,
        -1,
        3.4028234663852886e38,
        -3.4028234663852886e38,
        1.401298464324817e-45,
      ]);
      final tensor = OrtTensor.fromData(
        OrtElementType.float32,
        values,
        [values.length],
      );
      addTearDown(tensor.release);

      expect(tensor.view.float32s, values);
      expect(tensor.view.shape, [values.length]);
    });

    test('a tensor knows how many elements its shape implies', () {
      final tensor = OrtTensor.fromData(
        OrtElementType.float32,
        Float32List(24),
        [2, 3, 4],
      );
      addTearDown(tensor.release);

      expect(tensor.view.elementCount, 24);
    });
  }, skip: skipWithoutRuntime);
}

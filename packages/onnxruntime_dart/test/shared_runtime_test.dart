@Tags(['exclusive'])

/// The contract, on whichever platform this is, by whichever way of driving it.
///
/// Deliberately not `@TestOn('vm')`. Everything here goes through the public
/// API and the backend seam, so it is the same code on both platforms and the
/// same test should prove it on both.
///
/// Two things vary, and both are handled here rather than by writing the tests
/// twice. Whether a runtime is available at all, which `skipWithoutRuntime`
/// answers per platform. And which of the two ways of driving a session the
/// build accepts: the synchronous calls exist everywhere except an Asyncify
/// build of the web runtime, where a run can suspend, so the whole contract is
/// stated once and run through each.
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

/// One way of driving a session, so the expectations can be written once.
///
/// The asynchronous form works on every build. The synchronous form is the
/// same contract where the build offers it, and is skipped where it does not
/// rather than quietly going untested.
class Driver {
  const Driver(this.name, this.open, this.run, {this.skip});

  final String name;
  final Future<Session> Function(Uint8List model) open;
  final Future<Map<String, OrtTensor>> Function(
    Session session,
    Map<String, OrtTensor> feeds,
  ) run;
  final String? skip;
}

/// The drivers this build can be exercised through.
///
/// Asked after the runtime is open, because on the web which one applies is a
/// property of the module that was fetched, and there is nothing to ask before
/// that.
List<Driver> driversFor({required bool haveRuntime}) => [
      // No skip: nothing here asks for an accelerator, and a session that
      // stays on the CPU never suspends, so it runs synchronously on every
      // build, Asyncify included.
      Driver(
        'driven synchronously',
        (model) async => Session.fromBytes(model),
        (session, feeds) async => session.run(feeds),
      ),
      // Whatever this platform needs to run asynchronously: native wants
      // threads for the pool it dispatches onto, the web refuses to be asked.
      Driver(
        'driven asynchronously',
        (model) => Session.load(model, options: asyncSessionOptions),
        (session, feeds) => session.runAsync(feeds),
      ),
    ];

Future<void> main() async {
  // Before the groups are declared, because on the web the answer to
  // which drivers apply comes from the module that gets fetched here.
  await ensureRuntime();
  final drivers = driversFor(haveRuntime: skipWithoutRuntime == null);

  group('the runtime', () {
    test('reports a version', () {
      expect(runtimeVersion(), matches(RegExp(r'^\d+\.\d+\.\d+')));
    });

    test('lists the providers it was built with', () {
      final providers = availableProviders();
      expect(providers, isNotEmpty);
      expect(providers, contains('CPUExecutionProvider'));
    });

    test('says whether the synchronous calls are available', () {
      // Whatever the answer, at least one driver has to be able to run, or
      // this suite would pass by skipping everything.
      expect(drivers.where((d) => d.skip == null), isNotEmpty);
    });
  }, skip: skipWithoutRuntime);

  for (final driver in drivers) {
    group(driver.name, () {
      group('a session', () {
        late Session session;

        setUp(() async => session = await driver.open(absModel()));
        tearDown(() => session.release());

        test('reports what the model wants', () {
          expect(session.inputs, hasLength(1));
          expect(session.outputs, hasLength(1));
          expect(session.inputs.single.elementType, OrtElementType.float32);
        });

        test('reports a free dimension as one the model decides', () {
          // The model is declared [-1, -1, 5], so the first two are the
          // caller's choice and the last is not.
          expect(session.inputs.single.isDynamic, isTrue);
          expect(session.inputs.single.shape.last, 5);
        });

        test('runs and returns the right shape and values', () async {
          final input = OrtTensor.fromData(
            OrtElementType.float32,
            Float32List.fromList([-1, 2, -3, 4, -5, 6, -7, 8, -9, 10]),
            [1, 2, 5],
          );
          addTearDown(input.release);

          final outputs =
              await driver.run(session, {session.inputs.single.name: input});
          addTearDown(() {
            for (final output in outputs.values) {
              output.release();
            }
          });

          final view = outputs.values.single.view;
          expect(view.shape, [1, 2, 5]);
          expect(view.float32s, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
        });

        test('accepts a different shape for a free dimension', () async {
          // The point of a free dimension: one session, many batch sizes.
          for (final rows in [1, 3]) {
            final input = OrtTensor.fromData(
              OrtElementType.float32,
              Float32List(rows * 5)..fillRange(0, rows * 5, -2),
              [1, rows, 5],
            );
            final outputs =
                await driver.run(session, {session.inputs.single.name: input});

            expect(outputs.values.single.view.shape, [1, rows, 5]);
            expect(outputs.values.single.view.float32s.every((v) => v == 2),
                isTrue);

            input.release();
            for (final output in outputs.values) {
              output.release();
            }
          }
        });

        test('refuses an input of the wrong rank rather than reading past it',
            () async {
          final wrong = OrtTensor.fromData(
            OrtElementType.float32,
            Float32List.fromList([1, 2, 3]),
            [3],
          );
          addTearDown(wrong.release);

          await expectLater(
            driver.run(session, {session.inputs.single.name: wrong}),
            throwsA(isA<OrtException>()),
          );
        });

        test('refuses an input the model does not have', () async {
          final input = OrtTensor.fromData(
            OrtElementType.float32,
            Float32List(5),
            [1, 1, 5],
          );
          addTearDown(input.release);

          await expectLater(
            driver.run(session, {'not_an_input': input}),
            throwsA(anything),
          );
        });
      });

      group('handles', () {
        test('a released session refuses further use rather than crashing',
            () async {
          final session = await driver.open(absModel());
          final input = OrtTensor.fromData(
            OrtElementType.float32,
            Float32List(5),
            [1, 1, 5],
          );
          addTearDown(input.release);
          session.release();

          // Metadata was read when the session was built and is Dart-side, so
          // it survives. Anything that reaches the handle must not.
          await expectLater(
            driver.run(session, {session.inputs.single.name: input}),
            throwsA(isA<StateError>()),
          );
        });

        test('releasing twice is refused, not ignored', () async {
          final session = await driver.open(absModel());
          session.release();

          expect(session.release, throwsA(isA<StateError>()));
        });
      });
    }, skip: skipWithoutRuntime ?? driver.skip);
  }

  group('tensors', () {
    test('a released tensor refuses further use', () {
      final tensor = OrtTensor.fromData(
        OrtElementType.float32,
        Float32List(5),
        [1, 1, 5],
      );
      tensor.release();

      expect(() => tensor.view, throwsA(isA<StateError>()));
    });

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

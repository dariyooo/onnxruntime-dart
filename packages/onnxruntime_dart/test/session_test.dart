@TestOn('vm')
@Tags(['exclusive'])

/// Sessions across isolates and threads.
///
/// A session belongs to the isolate that built it, and ONNX Runtime's
/// environment is a process-wide singleton shared by all of them. That
/// combination is where the crashes were, so it is tested rather than assumed.
library;

import 'dart:io';
import 'dart:isolate';

import 'package:onnxruntime_dart/onnxruntime_dart.dart';
import 'package:test/test.dart';

import 'src/ort_library.dart';
import 'src/paths.dart';

Uint8ListOrBytes _model() => File(
      fromRoot(
        'third_party/onnxruntime/onnxruntime/test/testdata/'
        'ort_minimal_e2e_test_data/test_voice_commands/model.onnx',
      ),
    ).readAsBytesSync();

typedef Uint8ListOrBytes = List<int>;

void main() {
  group('Session', () {
    test('reports what the model takes and produces', () {
      final session = Session.fromBytes(_model());
      addTearDown(session.dispose);

      expect(session.inputs.single.name, 'input_1');
      expect(session.inputs.single.shape, [1, 6]);
      expect(session.inputs.single.elementType, OrtElementType.float32);
      expect(session.outputs.single.name, 'dense_1');
      expect(session.outputs.single.shape, [1, 26]);
    });

    test('rejects bytes that are not a model, rather than half-loading', () {
      expect(
        () => Session.fromBytes([0, 1, 2, 3, 4, 5, 6, 7]),
        throwsA(isA<OrtException>()),
      );
    });

    test('dispose frees once, and twice is refused', () {
      // Two disposes means two owners, which would double-free.
      final session = Session.fromBytes(_model());
      session.dispose();

      expect(session.isDisposed, isTrue);
      expect(session.dispose, throwsA(isA<StateError>()));
    });

    test('accepts configuration entries', () {
      // The general mechanism, and the only one the web has.
      final session = Session.fromBytes(
        _model(),
        options: const SessionOptions(
          config: {SessionConfig.disablePrepacking: '1'},
        ),
      );
      addTearDown(session.dispose);

      expect(session.inputs, isNotEmpty);
    });

    test('an unknown configuration key is accepted silently', () {
      // ONNX Runtime does not validate configuration keys: a typo is ignored
      // rather than reported, so the option never takes effect and nothing says
      // why. That is the reason the keys are generated from the headers.
      final session = Session.fromBytes(
        _model(),
        options: const SessionOptions(config: {'session.not_a_real_key': '1'}),
      );
      addTearDown(session.dispose);

      expect(session.inputs, isNotEmpty);
    });
  }, skip: skipWithoutNativeAsset);

  group('across isolates', () {
    test('a session built on a spawned isolate works there', () async {
      // The environment is process-wide, so a second isolate joins the existing
      // one rather than creating its own.
      final model = _model();
      final names = await Isolate.run(() {
        final session = Session.fromBytes(model);
        try {
          return session.inputs.map((i) => i.name).toList();
        } finally {
          session.dispose();
        }
      });

      expect(names, ['input_1']);
    });

    test('several isolates hold their own sessions at once', () async {
      // Each owns its own handle. Releasing one must not disturb the others,
      // and none may release the shared environment.
      final model = _model();
      final results = await Future.wait([
        for (var i = 0; i < 4; i++)
          Isolate.run(() {
            final session = Session.fromBytes(model);
            try {
              return session.outputs.single.shape.join(',');
            } finally {
              session.dispose();
            }
          }),
      ]);

      expect(results, everyElement('1,26'));
    });

    test('the main isolate keeps working after a worker exits', () {
      // A worker tearing down must not take the shared environment with it.
      final session = Session.fromBytes(_model());
      addTearDown(session.dispose);

      expect(session.inputs.single.name, 'input_1');
    });
  }, skip: skipWithoutNativeAsset);
}

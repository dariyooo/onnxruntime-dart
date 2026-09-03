@TestOn('vm')
@Tags(['exclusive'])

/// On-device training.
///
/// It cannot be loaded at run time: ONNX Runtime compiles it in or leaves it
/// out, which is the whole reason there are two builds. So most of this is
/// about the boundary being honest — a build without it says so, and one with
/// it reaches the real API rather than a null nobody checked.
library;

import 'dart:ffi';

import 'package:onnxruntime_dart/native.dart';
import 'package:test/test.dart';

import 'src/ort_library.dart';
import 'src/paths.dart';

void main() {
  group('availability', () {
    test('is read from the library, not from configuration', () {
      // ONNX Runtime returns null from GetTrainingApi on a build without it,
      // which is what this reports. Configuration can say anything.
      expect(trainingIsAvailable(), isA<bool>());
    });

    test('agrees with what the API hands back', () {
      if (trainingIsAvailable()) {
        expect(trainingApi(), isNot(equals(nullptr)));
      } else {
        expect(trainingApi, throwsA(isA<OrtTrainingUnavailable>()));
      }
    });

    test('a build without it says how to get one', () {
      expect(
        const OrtTrainingUnavailable().toString(),
        allOf(
          contains('variant: full'),
          contains('cannot be loaded at run time'),
        ),
      );
    });
  }, skip: skipWithoutOrt ?? skipWithoutNativeAsset);

  // Tagged, so a run against the base build does not attempt them at all
  // rather than attempting them and skipping. Training is compiled in or left
  // out, so on the base build there is nothing to test, and a skip there says
  // the same thing as a skip caused by a broken runtime.
  group('the training API', () {
    // Only the full build has these. The base build is what the workspace
    // installs, so these skip rather than fail.
    test('reaches checkpoints and steps', () {
      final api = trainingApi().ref;

      // The pointers are the API. If the struct were misaligned or the wrong
      // version, these would be null or nonsense.
      expect(api.LoadCheckpoint, isNot(equals(nullptr)));
      expect(api.CreateTrainingSession, isNot(equals(nullptr)));
      expect(api.TrainStep, isNot(equals(nullptr)));
      expect(api.OptimizerStep, isNot(equals(nullptr)));
      expect(api.ExportModelForInferencing, isNot(equals(nullptr)));
    });

    test('loads a real checkpoint and opens a training session on it', () {
      // Everything above proves the API is present. This proves it works:
      // ONNX Runtime ships a complete fixture set, so a checkpoint, a training
      // model, an eval model and an optimizer are all to hand.
      final fixtures = fromRoot(
        'third_party/onnxruntime/onnxruntime/test/testdata/training_api',
      );

      final api = trainingApi().ref;
      final checkpoint = api.loadCheckpoint('$fixtures/checkpoint.ckpt');
      expect(checkpoint, isNot(equals(nullptr)));
      addTearDown(() => api.releaseCheckpointState(checkpoint));

      final environment = OrtEnvironment.instance();
      final options = environment.api.createSessionOptions();
      addTearDown(() => environment.api.releaseSessionOptions(options));

      final session = api.createTrainingSession(
        environment.handle,
        options,
        checkpoint,
        '$fixtures/training_model.onnx',
        '$fixtures/eval_model.onnx',
        '$fixtures/adamw.onnx',
      );
      expect(session, isNot(equals(nullptr)));
      addTearDown(() => api.releaseTrainingSession(session));

      // Weights actually came off disk. A checkpoint that loaded but held
      // nothing would still hand back a session.
      expect(api.getParametersSize(session, true), greaterThan(0));

      // A real call into the training machinery, not just a handle check: it
      // walks the gradient buffers the session set up.
      expect(() => api.lazyResetGrad(session), returnsNormally);
    });

    test('reports a missing checkpoint rather than crashing', () {
      // The first thing any training run does is load a checkpoint, and the
      // first thing that goes wrong is the path.
      expect(
        () => trainingApi().ref.loadCheckpoint('/nonexistent/checkpoint'),
        throwsA(isA<OrtException>()),
      );
    });
  },
      tags: ['training'],
      skip: skipWithoutOrt ??
          skipWithoutNativeAsset ??
          (trainingIsAvailableSafely()
              ? null
              : 'this build has no training APIs (variant: full has them)'));
}

/// Whether training is available, without throwing when no runtime is loaded.
bool trainingIsAvailableSafely() {
  try {
    return trainingIsAvailable();
  } on Object {
    return false;
  }
}

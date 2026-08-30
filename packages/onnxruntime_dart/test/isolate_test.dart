@TestOn('vm')
@Tags(['exclusive'])

/// Running a model in a spawned isolate.
///
/// The package ships no pool and no sendable session: a session belongs to the
/// isolate that created it. What is owed is proof that creating one somewhere
/// else works and gives the same answer, since the runtime is shared process
/// state and that is where it would go wrong.
library;

import 'dart:isolate';
import 'dart:typed_data';

import 'package:onnxruntime_dart/onnxruntime_dart.dart';
import 'package:test/test.dart';

import 'src/ort_library.dart';
import 'src/tensor_proto.dart';
import 'src/test_models.dart';

void main() {
  group('a spawned isolate', () {
    test('produces the same output as the main isolate', () async {
      final model = voiceCommands.model();
      final input = TensorProto.decode(voiceCommands.input(0));

      final here =
          _infer((model: model, input: input.rawData, dims: input.dims));
      final there = await Isolate.run(
        () => _infer((model: model, input: input.rawData, dims: input.dims)),
      );

      expect(there, here);
    });

    test('several isolates can run at once', () async {
      // The environment is process-wide and created once. Isolates racing to
      // reach it first is the interesting case, so they start together.
      final model = voiceCommands.model();
      final input = TensorProto.decode(voiceCommands.input(0));
      final work = (model: model, input: input.rawData, dims: input.dims);

      final results = await Future.wait([
        for (var i = 0; i < 4; i++) Isolate.run(() => _infer(work)),
      ]);

      expect(results, everyElement(results.first));
    });
  }, skip: skipWithoutOrt ?? skipWithoutNativeAsset);
}

/// Loads the model, runs it once, and returns the output as plain data.
///
/// Plain data because nothing here is sendable: a `Session` and an `OrtTensor`
/// both own native memory belonging to the isolate that made them.
Float32List _infer(
  ({Uint8List model, Uint8List input, List<int> dims}) work,
) {
  final session = Session.fromBytes(work.model);
  try {
    final tensor = OrtTensor.fromData(
      OrtElementType.float32,
      work.input,
      work.dims,
    );
    try {
      final results = session.run({session.inputs.single.name: tensor});
      final output = results.values.single;
      try {
        // Copied, not viewed: the view borrows memory this function frees.
        return Float32List.fromList(
          Uint8List.fromList(output.view.data).buffer.asFloat32List(),
        );
      } finally {
        output.release();
      }
    } finally {
      tensor.release();
    }
  } finally {
    session.release();
  }
}

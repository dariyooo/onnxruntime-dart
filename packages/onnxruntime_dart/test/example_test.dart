@TestOn('vm')
@Tags(['exclusive'])

/// The examples, run.
///
/// An example that does not compile is worse than none, and one that compiles
/// but does not work is worse still. These are the two isolate patterns the
/// README points at, so they are the two worth proving.
library;

import 'dart:typed_data';

import 'package:test/test.dart';

import '../example/isolates.dart';
import 'src/ort_library.dart';
import 'src/tensor_proto.dart';
import 'src/test_models.dart';

void main() {
  group('the isolate examples', () {
    late Uint8List model;
    late Float32List input;
    late List<int> shape;

    setUpAll(() {
      model = voiceCommands.model();
      final proto = TensorProto.decode(voiceCommands.input(0));
      input = Uint8List.fromList(proto.rawData).buffer.asFloat32List();
      shape = proto.dims;
    });

    test('a short-lived isolate returns a result', () async {
      final result = await once(model, input, shape);
      expect(result, hasLength(26));
    });

    test('a worker answers repeated requests', () async {
      final worker = await InferenceWorker.start(model);
      addTearDown(worker.close);

      final first = await worker.infer(input, shape);
      final second = await worker.infer(input, shape);

      expect(second, first);
      expect(first, await once(model, input, shape));
    });
  }, skip: skipWithoutOrt ?? skipWithoutNativeAsset);
}

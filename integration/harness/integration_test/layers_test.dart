// The layers above the runtime, on a real device.
//
// The runtime and the WebGPU provider are covered by runtime_test.dart. These
// two ship for android and ios as well and were only ever run on desktop, so
// what nothing checked is the part that is actually different here: both are
// a second native library that has to be found and loaded next to the runtime
// after Android has mapped it out of an APK, or iOS has repackaged it into
// its own signed framework. A desktop job resolves a plain path on disk and
// cannot fail the way either of those can.
//
// Neither needs a model. The extensions contract is that ONNX Runtime accepts
// the library at all, and GenAI's handle types work before anything is
// loaded, so both are answerable on a device without shipping weights.
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:onnxruntime_dart/onnxruntime_dart.dart';
import 'package:onnxruntime_extensions/onnxruntime_extensions.dart'
    as extensions;
import 'package:onnxruntime_genai/onnxruntime_genai.dart';

import 'package:onnxruntime_harness/staged.dart';

/// A model with one Abs node, the same one the shared suite embeds.
///
/// Held here rather than loaded from an asset: what these tests are about is
/// libraries resolving, and a missing asset would fail them for an unrelated
/// reason.
final _absModel = Uint8List.fromList([
  8, 9, 58, 83, 10, 31, 10, 7, 105, 110, 112, 117, 116, 95, 48, 18, 8, 111, //
  117, 116, 112, 117, 116, 95, 48, 26, 3, 65, 98, 115, 34, 3, 65, 98, 115, //
  58, 0, 18, 3, 97, 98, 115, 90, 25, 10, 7, 105, 110, 112, 117, 116, 95, 48, //
  18, 14, 10, 12, 8, 1, 18, 8, 10, 2, 8, 2, 10, 2, 8, 4, 98, 16, 10, 8, 111, //
  117, 116, 112, 117, 116, 95, 48, 18, 4, 10, 2, 8, 1, 66, 4, 10, 0, 16, 21,
]);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('the extensions library on device', () {
    test('is installed and found', () {
      // Path recovery, the same fragile step the provider goes through. The
      // package is a dependency, so a null here means the asset never made it
      // into the bundle rather than that the library is broken.
      final path = extensions.extensionsPath();
      expect(
        path,
        isNotNull,
        reason: 'the package is a dependency, so its library must be found',
      );
      expect(path, contains(extensions.extensionsLibraryStem));
    });

    test('ONNX Runtime accepts it as a custom operator library', () {
      // The contract: a shared library exporting RegisterCustomOps that the
      // runtime will take. A wrong ABI or a missing export fails here, and on
      // Android this is also the first time the runtime dlopens something
      // that was mapped out of an APK rather than unpacked to disk.
      final session = Session.fromBytes(
        _absModel,
        options: SessionOptions(
          customOpsLibraries: [extensions.extensionsPath()!],
        ),
      );
      addTearDown(session.release);

      expect(session.inputs, hasLength(1));
    });

    test('a model still runs correctly with it loaded', () {
      // Registering hundreds of operators must not disturb a model that uses
      // none of them.
      final session = Session.fromBytes(
        _absModel,
        options: SessionOptions(
          customOpsLibraries: [extensions.extensionsPath()!],
        ),
      );
      addTearDown(session.release);

      // [2, 4], which is what the model declares. It was [1, 2, 4] and the
      // runtime rejected the rank rather than the values.
      final input = OrtTensor.fromData(
        OrtElementType.float32,
        Float32List.fromList([-1, 2, -3, 4, -5, 6, -7, 8]),
        [2, 4],
      );
      addTearDown(input.release);

      final outputs = session.run({session.inputs.single.name: input});
      addTearDown(() {
        for (final output in outputs.values) {
          output.release();
        }
      });

      expect(outputs.values.single.view.float32s, [1, 2, 3, 4, 5, 6, 7, 8]);
    });
  });

  group('GenAI on device', () {
    // Positive proof that this group ran, rather than the absence of a
    // failure. `flutter drive`, which the iOS job uses, reduces a passing run
    // to "All tests passed" and names no test, so a group that skipped and a
    // group that passed look identical there. A `skip:` on a group stops its
    // setUpAll too, so this line cannot be printed unless the body really
    // executed, and CI fails the job when it staged a GenAI library and this
    // does not appear. See .github/scripts/run_ios_harness.sh.
    setUpAll(() => print('harness: the GenAI group is running'));

    // No model anywhere in here. GenAI resolves OrtGetApiBase out of an ONNX
    // Runtime that is already loaded, so simply constructing a handle proves
    // the library was found and its dependency satisfied, which is the part
    // an APK or an embedded framework can break.
    test('the library loads and hands back a working handle', () {
      final sequences = Sequences();
      addTearDown(sequences.release);

      expect(sequences.count(), 0);
      sequences.appendTokenSequence([1, 2, 3]);
      expect(sequences.count(), 1);
      expect(sequences.getSequenceData(0), [1, 2, 3]);
    });

    test('a released handle refuses further use rather than crashing', () {
      final sequences = Sequences()..release();
      expect(sequences.isReleased, isTrue);
      expect(sequences.count, throwsA(isA<StateError>()));
    });

    test('a bad model path is an exception, not a crash', () {
      // The error path reaches into the library and back out. A device is
      // where a mishandled failure takes the process down with it.
      expect(() => Model('/no/such/model'), throwsA(isA<Exception>()));
    });
  }, skip: hasGenAi ? false : 'upstream ships no GenAI library for this ABI');

  // Outside the group above, deliberately. This was written inside it, where
  // it could never run: its own skip fires when a GenAI library is present,
  // and the group's skip fires when it is absent, so both branches skipped it
  // and the absence was never actually asserted anywhere.
  //
  // Upstream's .aar carries arm64-v8a and x86_64 only, so on a 32-bit row the
  // right answer is a clean refusal. A handle that somehow worked there would
  // mean the wrong library got loaded, which is worse than no library.
  test('GenAI is absent on an ABI upstream does not ship', () {
    expect(Sequences.new, throwsA(anything));
  }, skip: hasGenAi ? 'this ABI has a GenAI library' : false);
}

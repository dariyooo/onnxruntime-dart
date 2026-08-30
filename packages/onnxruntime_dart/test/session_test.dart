@TestOn('vm')
@Tags(['exclusive'])

/// Loading a model, running it, and reading what comes back.
///
/// The models and their reference outputs both come from the pinned submodule,
/// so a run is checked against what ONNX Runtime's own suite expects rather
/// than against a value recorded from an earlier run of this package.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:onnxruntime_dart/onnxruntime_dart.dart';
import 'package:test/test.dart';

import 'src/ort_library.dart';
import 'src/tensor_proto.dart';
import 'src/test_models.dart';

void main() {
  group('Session', () {
    late Session session;

    setUp(() => session = Session.fromBytes(voiceCommands.model()));
    tearDown(() => session.release());

    test('reports the model signature', () {
      expect(session.inputs, hasLength(1));
      expect(session.inputs.single.name, 'input_1');
      expect(session.inputs.single.elementType, OrtElementType.float32);
      expect(session.inputs.single.shape, [1, 6]);

      expect(session.outputs, hasLength(1));
      expect(session.outputs.single.name, 'dense_1');
      expect(session.outputs.single.shape, [1, 26]);
    });

    test('runs and matches the reference output', () {
      final input = TensorProto.decode(voiceCommands.input(0));
      final expected = TensorProto.decode(voiceCommands.output(0));

      final tensor = OrtTensor.fromData(
        OrtElementType.float32,
        input.rawData,
        input.dims,
      );
      addTearDown(tensor.release);

      final results = session.run({'input_1': tensor});
      addTearDown(() => _releaseAll(results.values));

      final view = results['dense_1']!.view;
      expect(view.elementType, OrtElementType.float32);
      expect(view.shape, expected.dims);
      expect(
        _floats(view.data),
        pairwiseCompare<double, double>(
          _floats(expected.rawData),
          (actual, want) => (actual - want).abs() < 1e-5,
          'within 1e-5 of the reference output',
        ),
      );
    });

    test('a missing input names what is missing', () {
      expect(
        () => session.run({}),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('input_1'),
          ),
        ),
      );
    });

    test('a released session cannot be used again', () {
      final other = Session.fromBytes(voiceCommands.model())..release();
      expect(other.endProfiling, throwsStateError);
      expect(other.release, throwsStateError);
    });
  }, skip: skipWithoutOrt ?? skipWithoutNativeAsset);

  group('rank-3 shapes', () {
    test('a bidirectional LSTM round-trips its reference data', () {
      final session = Session.fromBytes(bidirectionalLstm.model());
      addTearDown(session.release);

      final input = TensorProto.decode(bidirectionalLstm.input(0));
      final tensor = OrtTensor.fromData(
        OrtElementType.float32,
        input.rawData,
        input.dims,
      );
      addTearDown(tensor.release);

      expect(session.inputs.single.shape, hasLength(3));

      final results = session.run({session.inputs.single.name: tensor});
      addTearDown(() => _releaseAll(results.values));

      final expected = TensorProto.decode(bidirectionalLstm.output(0));
      expect(results.values.single.view.shape, expected.dims);
    });
  }, skip: skipWithoutOrt ?? skipWithoutNativeAsset);

  group('SessionOptions', () {
    test('every setting is accepted by the runtime', () {
      // Each one is a separate C call, and a wrong argument or a wrong enum
      // value is rejected at session creation rather than later.
      final directory = Directory.systemTemp.createTempSync('ort_options');
      addTearDown(() => directory.deleteSync(recursive: true));

      final session = Session.fromBytes(
        voiceCommands.model(),
        options: SessionOptions(
          intraOpNumThreads: 2,
          interOpNumThreads: 2,
          optimizationLevel: OrtOptimizationLevel.basic,
          executionMode: OrtExecutionMode.parallel,
          logLevel: OrtLogLevel.fatal,
          logId: 'options-test',
          optimizedModelPath: '${directory.path}/optimized.onnx',
          profileFilePrefix: '${directory.path}/profile',
          deterministicCompute: true,
          memoryPattern: false,
          cpuMemoryArena: false,
          config: const {'session.use_env_allocators': '0'},
          freeDimensionOverrides: const {'batch': 1},
        ),
      );
      addTearDown(session.release);

      expect(session.inputs, hasLength(1));

      // Two settings leave evidence on disk, which is the only way to tell
      // they were applied rather than accepted and ignored.
      expect(File('${directory.path}/optimized.onnx').existsSync(), isTrue);
      expect(session.endProfiling(), isNotNull);
    });

    test('an unknown provider is refused rather than falling back to CPU', () {
      expect(
        () => Session.fromBytes(
          voiceCommands.model(),
          options: const SessionOptions(
            providers: [(name: 'NotAProvider', configuration: {})],
          ),
        ),
        throwsA(isA<OrtException>()),
      );
    });
  }, skip: skipWithoutOrt ?? skipWithoutNativeAsset);

  group('the build', () {
    test('reports the providers it was compiled with', () {
      // CPU is always present; anything else depends on the build flags.
      expect(availableProviders(), contains('CPUExecutionProvider'));
    });

    test('reports the runtime version', () {
      expect(runtimeVersion(), matches(RegExp(r'^\d+\.\d+\.\d+')));
    });
  }, skip: skipWithoutOrt ?? skipWithoutNativeAsset);

  group('OrtTensor', () {
    test('rejects data that does not match the shape', () {
      expect(
        () => OrtTensor.fromData(
          OrtElementType.float32,
          Float32List(5),
          [2, 3],
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects a string tensor built from bytes', () {
      expect(
        () => OrtTensor.fromData(OrtElementType.string, Uint8List(0), [0]),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects strings that do not match the shape', () {
      expect(
        () => OrtTensor.fromStrings(['a', 'b'], [3]),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects a shape with a run-time dimension', () {
      // -1 means the model decides, which it cannot for something we are
      // building. Passing it through would allocate a tensor of no elements.
      expect(
        () => OrtTensor.fromData(
          OrtElementType.float32,
          Float32List(3),
          [-1, 3],
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}

/// Copies to an aligned buffer: a `raw_data` field starts wherever the message
/// puts it, and a typed-data view needs four-byte alignment.
Float32List _floats(Uint8List bytes) =>
    Uint8List.fromList(bytes).buffer.asFloat32List();

void _releaseAll(Iterable<OrtTensor> tensors) {
  for (final tensor in tensors) {
    tensor.release();
  }
}

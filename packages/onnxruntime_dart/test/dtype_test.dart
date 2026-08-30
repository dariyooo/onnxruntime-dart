@TestOn('vm')
@Tags(['exclusive'])

/// Every element type, in and back out again.
///
/// ONNX Runtime ships an identity model per type, so a round trip isolates the
/// conversion: anything that comes back different was mangled on the way
/// through, not computed differently.
library;

import 'dart:typed_data';

import 'package:onnxruntime_dart/onnxruntime_dart.dart';
import 'package:test/test.dart';

import 'src/ort_library.dart';
import 'src/test_models.dart';

/// Values chosen to catch sign and width mistakes: the extremes of each range,
/// and values that change if the bytes are reordered. Cycled to whatever length
/// the model wants, since the identity models do not agree on a shape.
final _cases = <String, (OrtElementType, TypedData Function(int))>{
  'float': (
    OrtElementType.float32,
    (n) => Float32List.fromList(_cycle(n, [-1.5, 0, 1, 2.25, 3])),
  ),
  'double': (
    OrtElementType.float64,
    (n) => Float64List.fromList(_cycle(n, [-1.5, 0, 1, 2.25, 3])),
  ),
  // No Dart type holds a half float, so the bits pass through opaquely.
  'float16': (
    OrtElementType.float16,
    (n) => Uint16List.fromList(_cycle(n, [0, 15360, 16384, 48128, 31743])),
  ),
  'int8': (
    OrtElementType.int8,
    (n) => Int8List.fromList(_cycle(n, [-128, -1, 0, 1, 127])),
  ),
  'uint8': (
    OrtElementType.uint8,
    (n) => Uint8List.fromList(_cycle(n, [0, 1, 127, 128, 255])),
  ),
  'int16': (
    OrtElementType.int16,
    (n) => Int16List.fromList(_cycle(n, [-32768, -1, 0, 1, 32767])),
  ),
  'uint16': (
    OrtElementType.uint16,
    (n) => Uint16List.fromList(_cycle(n, [0, 1, 255, 256, 65535])),
  ),
  'int32': (
    OrtElementType.int32,
    (n) => Int32List.fromList(_cycle(n, [-2147483648, -1, 0, 1, 2147483647])),
  ),
  'uint32': (
    OrtElementType.uint32,
    (n) => Uint32List.fromList(_cycle(n, [0, 1, 65535, 65536, 4294967295])),
  ),
  'int64': (
    OrtElementType.int64,
    (n) => Int64List.fromList(
          _cycle(n, [-9223372036854775808, -1, 0, 1, 9223372036854775807]),
        ),
  ),
  'uint64': (
    OrtElementType.uint64,
    (n) => Uint64List.fromList(_cycle(n, [0, 1, 4294967295, 4294967296, -1])),
  ),
  'bool': (
    OrtElementType.boolean,
    (n) => Uint8List.fromList(_cycle(n, [0, 1, 1, 0, 1])),
  ),
};

List<T> _cycle<T>(int count, List<T> values) =>
    List.generate(count, (i) => values[i % values.length]);

/// The shape to feed, with any run-time dimension pinned to one.
List<int> _shapeOf(OrtTensorMeta meta) =>
    [for (final dimension in meta.shape) dimension < 0 ? 1 : dimension];

void main() {
  group('round trip', () {
    for (final entry in _cases.entries) {
      test(entry.key, () {
        final (type, build) = entry.value;
        final session = _load(entry.key);
        addTearDown(session.release);

        expect(session.inputs.single.elementType, type);

        final shape = _shapeOf(session.inputs.single);
        final data = build(shape.fold(1, (a, b) => a * b));
        final tensor = OrtTensor.fromData(type, data, shape);
        addTearDown(tensor.release);

        final results = session.run({session.inputs.single.name: tensor});
        final output = results.values.single;
        addTearDown(output.release);

        final view = output.view;
        expect(view.elementType, type);
        expect(view.shape, shape);
        expect(
          view.data,
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          reason: '${entry.key} did not survive the round trip',
        );
      });
    }

    test('string', () {
      final session = _load('string');
      addTearDown(session.release);

      // Multi-byte and empty entries, because the contents come back as one
      // buffer plus offsets and both are where that goes wrong.
      final shape = _shapeOf(session.inputs.single);
      final values = _cycle(
        shape.fold(1, (a, b) => a * b),
        ['', 'a', 'héllo', '日本語', 'z' * 300],
      );
      final tensor = OrtTensor.fromStrings(values, shape);
      addTearDown(tensor.release);

      final results = session.run({session.inputs.single.name: tensor});
      final output = results.values.single;
      addTearDown(output.release);

      expect(output.strings, values);
    });

    test('reading a string tensor as bytes says to use strings', () {
      final session = _load('string');
      addTearDown(session.release);

      final shape = _shapeOf(session.inputs.single);
      final tensor = OrtTensor.fromStrings(
        _cycle(shape.fold(1, (a, b) => a * b), ['a']),
        shape,
      );
      addTearDown(tensor.release);

      expect(() => tensor.view, throwsStateError);
    });
  }, skip: skipWithoutOrt ?? skipWithoutNativeAsset);
}

/// Loads the identity model for [type], skipping when it is not in the corpus.
Session _load(String type) {
  final path = dtypeModels[type];
  if (path == null) {
    markTestSkipped('no identity model for $type');
    fail('no identity model for $type');
  }
  return Session.fromBytes(readSubmoduleFile(path));
}

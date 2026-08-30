/// Decoder tests built from synthetic bytes, so they run on every platform
/// including the browser. Vector tests that read models from disk live in
/// tensor_proto_vectors_test.dart.
library;

import 'dart:typed_data';

import 'package:test/test.dart';

import 'src/tensor_proto.dart';

void main() {
  group('rejects malformed input', () {
    test('missing data_type', () {
      // Field 9 (raw_data), length 0. No data_type.
      final bytes = Uint8List.fromList([0x4A, 0x00]);
      expect(
        () => TensorProto.decode(bytes),
        throwsA(isA<TensorProtoFormatException>()
            .having((e) => e.message, 'message', contains('data_type'))),
      );
    });

    test('missing raw_data', () {
      // Field 2 (data_type) = 1. No raw_data.
      final bytes = Uint8List.fromList([0x10, 0x01]);
      expect(
        () => TensorProto.decode(bytes),
        throwsA(isA<TensorProtoFormatException>()
            .having((e) => e.message, 'message', contains('raw_data'))),
      );
    });

    test('truncated varint', () {
      final bytes =
          Uint8List.fromList([0x10, 0x80]); // continuation bit, no next
      expect(
        () => TensorProto.decode(bytes),
        throwsA(isA<TensorProtoFormatException>()
            .having((e) => e.message, 'message', contains('truncated'))),
      );
    });

    test('length-delimited field overruns the buffer', () {
      // Field 9 (raw_data), claims 200 bytes, supplies none.
      final bytes = Uint8List.fromList([0x10, 0x01, 0x4A, 0xC8, 0x01]);
      expect(
        () => TensorProto.decode(bytes),
        throwsA(isA<TensorProtoFormatException>()
            .having((e) => e.message, 'message', contains('only 0 remain'))),
      );
    });

    test('unsupported wire type', () {
      final bytes =
          Uint8List.fromList([0x0B]); // field 1, wire type 3 (deprecated)
      expect(
        () => TensorProto.decode(bytes),
        throwsA(isA<TensorProtoFormatException>()
            .having((e) => e.message, 'message', contains('wire type 3'))),
      );
    });

    test('dims disagreeing with raw_data length is caught on access', () {
      // dims=[4] but only one float of raw_data.
      final builder = BytesBuilder()
        ..add([0x08, 0x04]) // field 1 (dims) varint 4
        ..add([0x10, 0x01]) // field 2 (data_type) = FLOAT
        ..add([0x4A, 0x04, 0, 0, 0, 0]); // field 9 (raw_data), 4 bytes
      final tensor = TensorProto.decode(builder.takeBytes());

      expect(tensor.dims, [4]);
      expect(
        tensor.asFloat32List,
        throwsA(isA<TensorProtoFormatException>()
            .having((e) => e.message, 'message', contains('16 bytes'))),
      );
    });

    test('reading as the wrong type is refused', () {
      final builder = BytesBuilder()
        ..add([0x10, 0x01]) // data_type = FLOAT
        ..add([0x4A, 0x04, 0, 0, 0, 0]);
      final tensor = TensorProto.decode(builder.takeBytes());

      expect(
        tensor.asInt64List,
        throwsA(isA<StateError>()
            .having((e) => e.message, 'message', contains('not int64'))),
      );
    });
  });

  group('unaligned raw_data', () {
    test('is decoded correctly despite a non-multiple byte offset', () {
      // A one-byte name puts raw_data at an odd offset, forcing a copy.
      final builder = BytesBuilder()
        ..add([0x10, 0x01]) // data_type = FLOAT
        ..add([0x42, 0x01, 0x78]) // field 8 (name) = "x"
        ..add([0x4A, 0x04, 0x00, 0x00, 0x80, 0x3F]); // raw_data = 1.0f
      final tensor = TensorProto.decode(builder.takeBytes());

      expect(tensor.rawData.offsetInBytes.isOdd, isTrue,
          reason: 'test is meaningless if raw_data happens to be aligned');
      expect(tensor.asFloat32List(), [1.0]);
    });
  });
}

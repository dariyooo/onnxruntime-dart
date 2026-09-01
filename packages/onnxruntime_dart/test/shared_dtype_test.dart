@Tags(['exclusive'])

/// Every element type, into a tensor and back out again.
///
/// Deliberately not `@TestOn('vm')`, and deliberately without a model. The two
/// backends write a tensor by different means, FFI against native memory and
/// heap writes against a WebAssembly module, and that is the code a round trip
/// isolates. `dtype_test.dart` runs the same types through ONNX Runtime's
/// identity models, which is stronger, but it reads them from the submodule
/// with `dart:io` and so can only run on the VM.
///
/// Values are the extremes of each range plus a few that change if the bytes
/// are reordered or the width is wrong.
library;

import 'dart:typed_data';

import 'package:onnxruntime_dart/onnxruntime_dart.dart';
import 'package:test/test.dart';

import 'src/runtime.dart';

/// Eight-byte values as raw bytes, little-endian.
///
/// Built by hand rather than with `Int64List`, which the web has no support
/// for: this is the only way to describe an int64 tensor in code that compiles
/// on both platforms.
Uint8List _eightByte(List<int> lowWords) {
  final bytes = Uint8List(lowWords.length * 8);
  final view = ByteData.view(bytes.buffer);
  for (var i = 0; i < lowWords.length; i++) {
    view.setUint32(i * 8, lowWords[i], Endian.little);
  }
  return bytes;
}

void main() {
  setUpAll(ensureRuntime);

  group('a tensor round-trips', () {
    final cases =
        <String, (OrtElementType, TypedData, Object Function(OrtTensorView))>{
      'float32': (
        OrtElementType.float32,
        Float32List.fromList([0, -0.0, 1, -1, 3.4028234663852886e38]),
        (v) => v.float32s,
      ),
      'float64': (
        OrtElementType.float64,
        Float64List.fromList([0, -1.5, 1.7976931348623157e308]),
        (v) => v.float64s,
      ),
      'int8': (
        OrtElementType.int8,
        Int8List.fromList([-128, -1, 0, 1, 127]),
        (v) => v.int8s,
      ),
      'uint8': (
        OrtElementType.uint8,
        Uint8List.fromList([0, 1, 128, 255]),
        (v) => v.uint8s,
      ),
      'int16': (
        OrtElementType.int16,
        Int16List.fromList([-32768, -1, 0, 1, 32767]),
        (v) => v.int16s,
      ),
      'uint16': (
        OrtElementType.uint16,
        Uint16List.fromList([0, 1, 32768, 65535]),
        (v) => v.uint16s,
      ),
      'int32': (
        OrtElementType.int32,
        Int32List.fromList([-2147483648, -1, 0, 1, 2147483647]),
        (v) => v.int32s,
      ),
      'uint32': (
        OrtElementType.uint32,
        Uint32List.fromList([0, 1, 2147483648, 4294967295]),
        (v) => v.uint32s,
      ),
      'float16': (
        // No Dart type for a half float, so the bits are the contract.
        OrtElementType.float16,
        Uint16List.fromList([0x0000, 0x3C00, 0xBC00, 0x7BFF]),
        (v) => v.float16Bits,
      ),
    };

    cases.forEach((name, testCase) {
      test(name, () {
        final (type, data, read) = testCase;
        // One dimension holding every element, so the shape is whatever the
        // data implies rather than a number repeated in each case.
        final tensor = OrtTensor.fromData(
          type,
          data,
          [data.lengthInBytes ~/ type.byteWidth!],
        );
        addTearDown(tensor.release);
        expect(read(tensor.view), data);
      });
    });
  }, skip: skipWithoutRuntime);

  group('a boolean tensor', () {
    test('is one byte per element, read back as booleans', () {
      final tensor = OrtTensor.fromData(
        OrtElementType.boolean,
        Uint8List.fromList([0, 1, 1, 0]),
        [4],
      );
      addTearDown(tensor.release);

      expect(tensor.view.bools, [false, true, true, false]);
    });
  }, skip: skipWithoutRuntime);

  group('a 64-bit integer tensor', () {
    test('can be built from bytes on either platform', () {
      final tensor = OrtTensor.fromData(
        OrtElementType.int64,
        _eightByte([0, 1, 2, 3]),
        [4],
      );
      addTearDown(tensor.release);

      expect(tensor.view.elementCount, 4);
      expect(tensor.view.elementType, OrtElementType.int64);
    });

    test('reads back as integers where the platform has them', () {
      final tensor = OrtTensor.fromData(
        OrtElementType.int64,
        _eightByte([0, 1, 2, 3]),
        [4],
      );
      addTearDown(tensor.release);

      // dart2js has no Int64List, so this is the one accessor that genuinely
      // differs between the platforms. It should say so, and say what to do
      // instead, rather than throwing dart2js's own message.
      if (identical(1, 1.0)) {
        expect(
          () => tensor.view.int64s,
          throwsA(
            isA<UnsupportedError>().having(
              (e) => e.message,
              'message',
              allOf(contains('view.data'), contains('JavaScript build')),
            ),
          ),
        );
        // The bytes are still there, which is the documented way out.
        expect(tensor.view.data, hasLength(32));
      }

      // The portable accessor reads the same values on either platform, which
      // is the point of it.
      expect(tensor.view.int64Values, [0, 1, 2, 3]);
    });

    test('refuses a value it cannot represent rather than rounding it', () {
      // Two words, so the value needs more than 53 bits. Native reads it;
      // a JavaScript build has to refuse rather than hand back a rounded one.
      final bytes = Uint8List(8);
      ByteData.view(bytes.buffer)
        ..setUint32(0, 1, Endian.little)
        ..setUint32(4, 0x00400000, Endian.little);
      final tensor = OrtTensor.fromData(OrtElementType.int64, bytes, [1]);
      addTearDown(tensor.release);

      if (identical(1, 1.0)) {
        expect(
          () => tensor.view.int64Values,
          throwsA(isA<UnsupportedError>()
              .having((e) => e.message, 'message', contains('53 bits'))),
        );
      } else {
        // 0x0040000000000001, which needs 55 bits. Computed rather than
        // written out: dart2js refuses to compile the literal at all, which
        // is the same limit this test is about.
        expect(tensor.view.int64Values, [0x00400000 * 4294967296 + 1]);
      }
    });
  }, skip: skipWithoutRuntime);
}

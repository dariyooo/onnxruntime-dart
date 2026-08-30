@TestOn('browser')

/// The shared library, compiled for the web.
///
/// Nothing here calls the runtime. What is being checked is that
/// `onnxruntime_dart.dart` compiles for a browser at all: an accidental
/// `dart:ffi` reference anywhere below it makes the whole library unusable
/// there, and the failure is at compile time in the user's app rather than
/// anywhere we would otherwise notice.
library;

import 'dart:typed_data';

import 'package:onnxruntime_dart/onnxruntime_dart.dart';
import 'package:test/test.dart';

void main() {
  test('the shared library compiles and its value types work', () {
    expect(OrtElementType.fromCode(1), OrtElementType.float32);
    expect(
      const OrtTensorMeta(
        name: 'input',
        elementType: OrtElementType.float32,
        shape: [-1, 3],
      ).isDynamic,
      isTrue,
    );
  });

  test('the runtime is not available, and says so', () {
    // The WebAssembly backend is not implemented yet. Until it is, reaching
    // the runtime must fail loudly rather than appear to work.
    expect(
      () => Session.fromBytes(Uint8List(0)),
      throwsA(isA<UnsupportedError>()),
    );
  });
}

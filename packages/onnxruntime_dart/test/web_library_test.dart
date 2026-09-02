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

  test('reaching the runtime before loading it says which call is missing', () {
    // The WebAssembly module has to be fetched and instantiated, which cannot
    // happen synchronously, so an application calls openOnnxRuntime once at
    // startup. Using the runtime before that must name that call rather than
    // failing somewhere inside the backend.
    expect(
      () => Session.fromBytes(Uint8List(0)),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('loadOrtWasm'),
        ),
      ),
    );
  });

  test('a JSPI build is refused rather than driven as a synchronous one', () {
    // The failure this prevents is silent: a JSPI build defines no asyncInit,
    // so it would be taken for the plain build and its promises read as
    // numbers. Nothing would throw and every result would be wrong.
    expect(
      () => openOnnxRuntime(
        web: const WebRuntimeOptions(
          'https://example.test/ort-wasm-simd-threaded.jspi.mjs',
        ),
      ),
      throwsA(
        isA<UnsupportedError>().having(
          (e) => e.message,
          'message',
          allOf(contains('JSPI'), contains('asyncify')),
        ),
      ),
    );
  });

  test('openOnnxRuntime needs somewhere to fetch the runtime from', () {
    // Native has the library already; the web has to be told where it is.
    // Saying so is better than a failure inside the loader.
    expect(
      () => openOnnxRuntime(),
      throwsA(isA<ArgumentError>()),
    );
  });
}

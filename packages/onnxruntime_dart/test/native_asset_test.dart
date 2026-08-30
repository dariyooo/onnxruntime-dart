@TestOn('vm')

/// The build hook resolves ONNX Runtime and declares it as a code asset, so
/// nothing here opens a library by path. A failure means the hook did not
/// produce a usable asset, which is the whole point of it.
library;

import 'dart:io';

import 'package:onnxruntime_dart/src/bindings/ort_bindings.g.dart';
import 'package:onnxruntime_dart/src/ffi/runtime.dart';
import 'package:test/test.dart';

import 'src/ort_library.dart';
import 'src/paths.dart';

void main() {
  group('code asset', () {
    test('resolves without a library path', () {
      final version = runtimeVersion();
      final pinned = File(fromRoot('third_party/onnxruntime/VERSION_NUMBER'))
          .readAsStringSync()
          .trim();

      expect(version, pinned,
          reason: 'the bundled asset should be the version the submodule pins');
    });

    test('the runtime accepts the API version the bindings were built for', () {
      expect(ortApi(), isNot(equals(0)));
    });

    test('reports a version mismatch rather than returning a null api', () {
      // ortApi() throws instead of handing back nullptr, so callers cannot
      // dereference a null OrtApi.
      expect(OrtAbiMismatch(999, '1.29.0').toString(),
          allOf(contains('999'), contains('1.29.0')));
    });

    test('ORT_API_VERSION matches the header the bindings came from', () {
      expect(ORT_API_VERSION, 29);
    });
  }, skip: skipWithoutNativeAsset);
}

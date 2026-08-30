/// Entry point into the ONNX Runtime C API.
///
/// `OrtGetApiBase` is the only symbol the library exports as a free function.
/// Every other call is a field on the `OrtApi` struct it hands back, so binding
/// this one function is enough to reach the entire API.
///
/// It resolves against the code asset the build hook provides, so nothing here
/// needs a library path.
library;

import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../bindings/ort_bindings.g.dart';
import '../exceptions.dart';

export '../exceptions.dart' show OrtAbiMismatch;

/// Asset id declared by `hook/build.dart`.
const _assetId = 'package:onnxruntime_dart/onnxruntime';

@Native<Pointer<OrtApiBase> Function()>(
  symbol: 'OrtGetApiBase',
  assetId: _assetId,
)
external Pointer<OrtApiBase> _ortGetApiBase();

/// The version of ONNX Runtime that is loaded, such as `1.29.0`.
String runtimeVersion() {
  final base = _ortGetApiBase();
  return base.ref.GetVersionString
      .asFunction<Pointer<Char> Function()>()()
      .cast<Utf8>()
      .toDartString();
}

/// The `OrtApi` matching the version these bindings were generated against.
///
/// Throws [OrtAbiMismatch] when the loaded library predates that version, which
/// means the binary and the bindings disagree about the ABI.
Pointer<OrtApi> ortApi() {
  final base = _ortGetApiBase();
  final api = base.ref.GetApi
      .asFunction<Pointer<OrtApi> Function(int)>()(ORT_API_VERSION);
  if (api == nullptr) {
    throw OrtAbiMismatch(ORT_API_VERSION, runtimeVersion());
  }
  return api;
}

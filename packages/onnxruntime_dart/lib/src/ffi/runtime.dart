/// Entry point into the ONNX Runtime C API.
///
/// `OrtGetApiBase` is the only symbol the library exports as a free function.
/// Every other call is a field on the `OrtApi` struct it hands back, so binding
/// this one function is enough to reach the entire API. That is also why
/// choosing a runtime costs so little: it is one binding, resolved once.
///
/// This package ships no binaries. The library comes from
/// `onnxruntime_binaries`, whose version is the ONNX Runtime version:
///
/// ```yaml
/// dependencies:
///   onnxruntime_dart: ^0.1.0
///   onnxruntime_binaries: ^1.29.0
/// ```
///
/// One package rather than one per variant, so exactly one library can ever be
/// installed. Two packages could both be depended on, and pub has no way to
/// say that two packages are mutually exclusive.
library;

import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../bindings/ort_bindings.g.dart';
import '../exceptions.dart';

export '../exceptions.dart' show OrtAbiMismatch;

@Native<Pointer<OrtApiBase> Function()>(
  symbol: 'OrtGetApiBase',
  assetId: 'package:onnxruntime_binaries/onnxruntime',
)
external Pointer<OrtApiBase> _apiBase();

/// Thrown when no runtime is installed.
final class OrtRuntimeMissing implements Exception {
  const OrtRuntimeMissing();

  @override
  String toString() =>
      'No ONNX Runtime is installed. onnxruntime_dart ships the bindings but '
      'no binaries, so add the runtime to pubspec.yaml:\n'
      '\n'
      '  dependencies:\n'
      '    onnxruntime_binaries: ^1.29.0\n';
}

/// Whether the installed runtime was built with the on-device training APIs.
///
/// True when `onnxruntime_binaries` was asked for the `full` variant. Read from
/// the library rather than from configuration, because the library is what has
/// to support the call: ONNX Runtime returns null here on a build without it.
bool trainingIsAvailable() =>
    ortApi()
        .ref
        .GetTrainingApi
        .asFunction<Pointer<OrtTrainingApi> Function(int)>()(ORT_API_VERSION) !=
    nullptr;

/// The version of ONNX Runtime that is loaded, such as `1.29.0`.
String runtimeVersion() => _apiBase()
    .ref
    .GetVersionString
    .asFunction<Pointer<Char> Function()>()()
    .cast<Utf8>()
    .toDartString();

/// The `OrtApi` matching the version these bindings were generated against.
///
/// Throws [OrtAbiMismatch] when the loaded library predates that version, which
/// means the binary and the bindings disagree about the ABI.
Pointer<OrtApi> ortApi() {
  final base = _apiBase();
  final api = base.ref.GetApi
      .asFunction<Pointer<OrtApi> Function(int)>()(ORT_API_VERSION);
  if (api == nullptr) {
    throw OrtAbiMismatch(ORT_API_VERSION, runtimeVersion());
  }
  return api;
}

/// Entry point into the ONNX Runtime C API.
///
/// `OrtGetApiBase` is the only symbol the library exports as a free function.
/// Every other call is a field on the `OrtApi` struct it hands back, so binding
/// this one function is enough to reach the entire API. That is also why
/// choosing a runtime costs so little: it is one binding, resolved once.
///
/// This package ships no binaries. The library comes from whichever runtime
/// package the application depends on, and which one that is decides both the
/// ONNX Runtime version and whether training is compiled in:
///
/// ```yaml
/// dependencies:
///   onnxruntime_dart: ^0.1.0
///   onnxruntime_base: ^1.29.0        # or onnxruntime_full
/// ```
///
/// Each candidate is a separate `@Native`, because an asset id is a
/// compile-time constant and a hook may only publish assets named for its own
/// package. Declaring one that nothing provides is harmless: it fails only if
/// it is called, which is what makes probing them possible.
library;

import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../bindings/ort_bindings.g.dart';
import '../exceptions.dart';

export '../exceptions.dart' show OrtAbiMismatch;

@Native<Pointer<OrtApiBase> Function()>(
  symbol: 'OrtGetApiBase',
  assetId: 'package:onnxruntime_base/onnxruntime',
)
external Pointer<OrtApiBase> _base();

@Native<Pointer<OrtApiBase> Function()>(
  symbol: 'OrtGetApiBase',
  assetId: 'package:onnxruntime_full/onnxruntime',
)
external Pointer<OrtApiBase> _full();

/// Thrown when no runtime package is installed.
final class OrtRuntimeMissing implements Exception {
  const OrtRuntimeMissing();

  @override
  String toString() =>
      'No ONNX Runtime is installed. onnxruntime_dart ships the bindings but '
      'no binaries, so add the runtime you want to pubspec.yaml:\n'
      '\n'
      '  dependencies:\n'
      '    onnxruntime_base: ^1.29.0        # every operator and provider\n'
      '    # or, for on-device training:\n'
      '    onnxruntime_full: ^1.29.0\n';
}

/// `OrtGetApiBase` from whichever runtime package is installed.
///
/// Both are tried because only the installed one has an asset. Which of them
/// answered is deliberately not reported: a missing asset falls back to a
/// process-wide symbol lookup, so once the library is loaded by anything the
/// other binding resolves too, and the answer would be whichever ran first.
/// [trainingIsAvailable] asks the library what it can do instead, which is the
/// question worth asking.
final Pointer<OrtApiBase> Function() _apiBase = _resolveRuntime();

Pointer<OrtApiBase> Function() _resolveRuntime() {
  for (final candidate in [_full, _base]) {
    try {
      candidate();
      return candidate;
    } on ArgumentError {
      // Nothing publishes this asset and the symbol is nowhere in the process,
      // so this runtime package is not installed.
      continue;
    }
  }
  throw const OrtRuntimeMissing();
}

/// Whether the installed runtime was built with the on-device training APIs.
///
/// True with `onnxruntime_full`, false with `onnxruntime_base`.
/// Read from the library rather than from which package is installed, because
/// the library is what has to support the call.
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

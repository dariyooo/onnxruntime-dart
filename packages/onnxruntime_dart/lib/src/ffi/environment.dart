/// The process-wide ONNX Runtime environment.
///
/// `CreateEnv` returns the same instance on every call and ignores its
/// arguments after the first, so this is a lookup rather than a construction.
/// That is also why an environment can be obtained from any isolate without
/// coordinating.
library;

import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../bindings/ort_bindings.g.dart';
import 'runtime.dart';
import 'status.dart';

/// Handle to the shared environment, with the API it was resolved from.
final class OrtEnvironment {
  OrtEnvironment._(this.api, this.handle);

  /// The `OrtApi` matching the bound API version.
  final OrtApi api;

  /// The process-wide `OrtEnv`.
  final Pointer<OrtEnv> handle;

  static OrtEnvironment? _instance;

  /// Returns the environment, creating it on first use.
  ///
  /// Never released: ONNX Runtime owns the singleton and tears it down with the
  /// process, so releasing it from one isolate would break every other.
  factory OrtEnvironment.instance({
    int loggingLevel = 3, // ORT_LOGGING_LEVEL_ERROR
    String logId = 'onnxruntime_dart',
  }) {
    final existing = _instance;
    if (existing != null) return existing;

    final api = ortApi().ref;
    final arena = Arena();
    try {
      final out = arena<Pointer<OrtEnv>>();
      checkStatus(
        api,
        api.CreateEnv.asFunction<
            Pointer<OrtStatus> Function(
              int,
              Pointer<Char>,
              Pointer<Pointer<OrtEnv>>,
            )>()(
          loggingLevel,
          logId.toNativeUtf8(allocator: arena).cast(),
          out,
        ),
      );
      return _instance = OrtEnvironment._(api, out.value);
    } finally {
      arena.releaseAll();
    }
  }
}

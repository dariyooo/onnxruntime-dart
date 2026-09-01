/// Session options, buffered until the runtime will take them.
///
/// The one place the two APIs disagree structurally. Native hands out an
/// options object and mutates it through a setter per field. The WebAssembly
/// build takes every field as a parameter of `OrtCreateSessionOptions` and has
/// no setters at all.
///
/// So the seam's setters record into this, and the object is built when the
/// session is created. A handle is still handed back so the seam's shape does
/// not change, but it names one of these rather than anything in the heap.
library;

import '../types.dart';

/// What the wasm build accepts, with the defaults it uses when unset.
final class PendingSessionOptions {
  /// `ORT_ENABLE_ALL`, matching the native default.
  int optimizationLevel = 99;

  bool cpuMemoryArena = true;
  bool memoryPattern = true;

  /// Sequential.
  int executionMode = 0;

  bool profiling = false;
  String? profilePrefix;
  String? logId;

  /// Warning.
  int logSeverity = 2;
  int logVerbosity = 0;
  String? optimizedModelPath;

  /// Entries applied after creation, which the wasm build does support.
  final config = <String, String>{};

  /// Providers to append, in order, with their own configuration.
  final providers = <(String, Map<String, String>)>[];

  /// Free dimension overrides, applied after creation.
  final freeDimensions = <String, int>{};

  void setOptimization(OrtOptimizationLevel level) =>
      optimizationLevel = level.code;

  void setExecution(OrtExecutionMode mode) => executionMode = mode.code;

  void setLog(OrtLogLevel level) => logSeverity = level.code;
}

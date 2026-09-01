/// The functions ONNX Runtime's WebAssembly build exports.
///
/// One per `EMSCRIPTEN_KEEPALIVE` in `onnxruntime/wasm/api.h`, under its
/// Emscripten name. Handles and pointers are plain integers, and everything
/// crossing here is already marshalled: see `arena.dart`.
///
/// The convention differs from the native C API. Instead of returning a status
/// object, a call returns either a handle, where zero means failure, or an
/// error code, where zero means success. Either way the detail comes from
/// `OrtGetLastError`, which is what [check] and [checkHandle] read.
library;

import 'dart:js_interop';

import '../../exceptions.dart';
import 'module.dart';

extension OrtWasmApi on OrtModule {
  @JS('_OrtInit')
  external JSNumber ortInit(JSNumber numThreads, JSNumber loggingLevel);

  @JS('_OrtGetLastError')
  external JSNumber ortGetLastError(JSNumber codeOut, JSNumber messageOut);

  @JS('_OrtCreateSessionOptions')
  external JSNumber ortCreateSessionOptions(
    JSNumber graphOptimizationLevel,
    JSBoolean enableCpuMemArena,
    JSBoolean enableMemPattern,
    JSNumber executionMode,
    JSBoolean enableProfiling,
    JSNumber profileFilePrefix,
    JSNumber logId,
    JSNumber logSeverityLevel,
    JSNumber logVerbosityLevel,
    JSNumber optimizedModelPath,
  );

  @JS('_OrtAppendExecutionProvider')
  external JSNumber ortAppendExecutionProvider(JSNumber options, JSNumber name,
      JSNumber keys, JSNumber values, JSNumber count);

  @JS('_OrtAddSessionConfigEntry')
  external JSNumber ortAddSessionConfigEntry(
      JSNumber options, JSNumber key, JSNumber value);

  @JS('_OrtAddFreeDimensionOverride')
  external JSNumber ortAddFreeDimensionOverride(
      JSNumber options, JSNumber name, JSNumber dimension);

  @JS('_OrtReleaseSessionOptions')
  external JSNumber ortReleaseSessionOptions(JSNumber options);

  @JS('_OrtCreateSession')
  external JSNumber ortCreateSession(
      JSNumber data, JSNumber length, JSNumber options);

  @JS('_OrtReleaseSession')
  external JSNumber ortReleaseSession(JSNumber session);

  @JS('_OrtGetInputOutputCount')
  external JSNumber ortGetInputOutputCount(
      JSNumber session, JSNumber inputsOut, JSNumber outputsOut);

  @JS('_OrtGetInputOutputMetadata')
  external JSNumber ortGetInputOutputMetadata(
      JSNumber session, JSNumber index, JSNumber nameOut, JSNumber typeInfoOut);

  @JS('_OrtFree')
  external JSNumber ortFree(JSNumber pointer);

  @JS('_OrtCreateTensor')
  external JSNumber ortCreateTensor(
      JSNumber dataType,
      JSNumber data,
      JSNumber dataLength,
      JSNumber dims,
      JSNumber dimsLength,
      JSNumber location);

  @JS('_OrtGetTensorData')
  external JSNumber ortGetTensorData(JSNumber tensor, JSNumber typeOut,
      JSNumber dataOut, JSNumber dimsOut, JSNumber dimsLengthOut);

  @JS('_OrtReleaseTensor')
  external JSNumber ortReleaseTensor(JSNumber tensor);

  @JS('_OrtCreateRunOptions')
  external JSNumber ortCreateRunOptions(JSNumber logSeverityLevel,
      JSNumber logVerbosityLevel, JSBoolean terminate, JSNumber tag);

  @JS('_OrtAddRunConfigEntry')
  external JSNumber ortAddRunConfigEntry(
      JSNumber runOptions, JSNumber key, JSNumber value);

  @JS('_OrtReleaseRunOptions')
  external JSNumber ortReleaseRunOptions(JSNumber runOptions);

  @JS('_OrtRun')
  external JSNumber ortRun(
    JSNumber session,
    JSNumber inputNames,
    JSNumber inputs,
    JSNumber inputCount,
    JSNumber outputNames,
    JSNumber outputCount,
    JSNumber outputs,
    JSNumber runOptions,
  );

  @JS('_OrtCreateBinding')
  external JSNumber ortCreateBinding(JSNumber session);

  @JS('_OrtBindInput')
  external JSNumber ortBindInput(
      JSNumber binding, JSNumber name, JSNumber tensor);

  @JS('_OrtBindOutput')
  external JSNumber ortBindOutput(
      JSNumber binding, JSNumber name, JSNumber tensor, JSNumber location);

  @JS('_OrtClearBoundOutputs')
  external JSNumber ortClearBoundOutputs(JSNumber binding);

  @JS('_OrtReleaseBinding')
  external JSNumber ortReleaseBinding(JSNumber binding);

  @JS('_OrtRunWithBinding')
  external JSNumber ortRunWithBinding(JSNumber session, JSNumber binding,
      JSNumber outputCount, JSNumber outputs, JSNumber runOptions);

  @JS('_OrtEndProfiling')
  external JSNumber ortEndProfiling(JSNumber session);
}

/// What the runtime last failed with: its `OrtErrorCode` and its message.
///
/// The message lives in the module's heap and belongs to it, so it is read out
/// rather than kept.
({int code, String message}) lastError(OrtModule module) {
  final slots = module.allocateSlot(2);
  try {
    module.ortGetLastError(slots.toJS, (slots + 4).toJS);
    final message = module.readPointer(slots + 4);
    return (
      code: module.readInt(slots),
      message: message == 0 ? 'no detail' : module.readString(message),
    );
  } finally {
    module.free(slots);
  }
}

/// Throws unless [code] is zero, which is how a call reports success.
void check(OrtModule module, int code, String what) {
  if (code == 0) return;
  final error = lastError(module);
  throw OrtException(error.code, '$what failed: ${error.message}');
}

/// Throws unless [handle] is non-zero, which is how a call reports success.
int checkHandle(OrtModule module, int handle, String what) {
  if (handle != 0) return handle;
  final error = lastError(module);
  throw OrtException(error.code, '$what failed: ${error.message}');
}

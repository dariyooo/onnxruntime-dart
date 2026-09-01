/// Turning a WebAssembly call's result into an exception.
///
/// The convention differs from the native C API. There a call returns an
/// `OrtStatus` to read and release; here it returns either a handle, where
/// zero means failure, or an error code, where zero means success. Either way
/// the detail comes from `OrtGetLastError`.
library;

import 'dart:js_interop';

import '../../exceptions.dart';
import 'api.g.dart';
import 'module.dart';

/// What the runtime last failed with: its `OrtErrorCode` and its message.
///
/// The message belongs to the module's heap, so it is read out rather than
/// kept.
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

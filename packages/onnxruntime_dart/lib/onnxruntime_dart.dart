/// Pure-Dart bindings to ONNX Runtime.
///
/// This library holds the ergonomic API. It is deliberately smaller than the
/// runtime's full surface, and it grows to cover what callers actually reach
/// for.
///
/// It is not the limit of what the package can do. `native.dart` exposes the
/// complete C API, generated from the pinned headers, and this library is built
/// on it. Anything missing here is reachable there.
library;

export 'src/annotations.dart' show NativeOnly, unsupportedOnWeb;
export 'src/ffi/runtime.dart' show OrtAbiMismatch, runtimeVersion;
export 'src/ffi/status.dart' show OrtException;

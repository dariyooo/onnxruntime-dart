/// The complete ONNX Runtime C API.
///
/// Every function in `OrtApi` is reachable here, because the bindings are
/// generated from the pinned headers rather than hand-written. That makes
/// completeness a property of the package instead of a goal: anything the C API
/// can do, this library can do on the day the header ships it.
///
/// [ortApi] returns the `OrtApi` struct, whose fields are the function pointers:
///
/// ```dart
/// final api = ortApi().ref;
/// final out = calloc<Pointer<OrtAllocator>>();
/// api.GetAllocatorWithDefaultOptions
///     .asFunction<Pointer<OrtStatus> Function(Pointer<Pointer<OrtAllocator>>)>()(out);
/// ```
///
/// Callers here own every handle they create and must release it, and must read
/// and release every `OrtStatus`. [checkStatus] does the latter correctly on
/// both paths.
///
/// The ergonomic API in `onnxruntime_dart.dart` covers the common path and is
/// built on exactly these calls. It is a convenience, never a ceiling: reaching
/// for this library is expected, not a workaround.
library;

export 'src/bindings/ort_bindings.g.dart';
export 'src/ffi/environment.dart';
export 'src/ffi/execution_provider.dart';
export 'src/ffi/ort_path.dart' show allocateOrtPath, ortPathIsWide, readOrtPath;
export 'src/ffi/runtime.dart' show OrtAbiMismatch, ortApi, runtimeVersion;
export 'src/ffi/status.dart';

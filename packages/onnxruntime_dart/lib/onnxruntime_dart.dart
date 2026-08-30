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
export 'src/backend/types.dart'
    show OrtElementType, OrtTensorMeta, OrtTensorView;
export 'src/bindings/config_keys.g.dart';
export 'src/exceptions.dart' show OrtAbiMismatch, OrtException;
export 'src/session.dart'
    show OrtTensor, Session, SessionOptions, availableProviders, runtimeVersion;

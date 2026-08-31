/// Everything that needs the native loader.
///
/// That is the complete ONNX Runtime C API, and also the calls that are
/// ergonomic rather than raw but cannot live in `onnxruntime_dart.dart`:
/// registering a bundled provider means asking the loader where a library
/// came from, and the shared library must compile for the web.
///
/// Every function in `OrtApi` is reachable here, because the bindings are
/// generated from the pinned headers rather than hand-written. That makes
/// completeness a property of the package instead of a goal: anything the C API
/// can do, this library can do on the day the header ships it.
///
/// [ortApi] returns the `OrtApi` struct. Its fields are raw function pointers,
/// and each one also has a generated wrapper that takes and returns Dart
/// values, allocates what the call needs, and turns a failed `OrtStatus` into an
/// [OrtException]:
///
/// ```dart
/// final api = ortApi().ref;
/// final allocator = api.getAllocatorWithDefaultOptions();
/// final name = api.sessionGetInputName(session, 0, allocator);
/// ```
///
/// The raw pointer is still there when a call needs something the wrapper does
/// not express, such as a callback. Calling it means reading and releasing the
/// `OrtStatus` by hand, which [checkStatus] does correctly on both paths.
///
/// Handles are not owned by anything here: whatever a call creates, the caller
/// releases.
///
/// The ergonomic API in `onnxruntime_dart.dart` covers the common path and is
/// built on exactly these calls. It is a convenience, never a ceiling: reaching
/// for this library is expected, not a workaround.
library;

export 'src/bindings/api/api.g.dart';
export 'src/bindings/api/support.dart' show withArena;
export 'src/bindings/ort_bindings.g.dart';
export 'src/ffi/bundled_extensions.dart' show extensionsLibraryPath;
export 'src/ffi/bundled_provider.dart'
    show OrtExecutionProvider, bundledProviderPath, registerBundledProviders;
export 'src/ffi/environment.dart';
export 'src/ffi/execution_provider.dart';
export 'src/ffi/library_path.dart' show libraryPathOf;
export 'src/ffi/ort_path.dart' show allocateOrtPath, ortPathIsWide, readOrtPath;
export 'src/ffi/runtime.dart'
    show
        OrtAbiMismatch,
        OrtRuntimeMissing,
        OrtTrainingUnavailable,
        ortApi,
        runtimeVersion,
        trainingApi,
        trainingIsAvailable;
export 'src/ffi/status.dart';

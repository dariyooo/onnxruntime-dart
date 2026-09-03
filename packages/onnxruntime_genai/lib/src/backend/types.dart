/// Types crossing the boundary between the shared code and a backend.
///
/// None of them mention `dart:ffi`, so everything above the boundary compiles
/// for the web as well as for native. One `dart:ffi` import above this line
/// breaks the package in a consumer's web build rather than in ours.
library;

/// An opaque handle into backend memory.
///
/// Native, this is a pointer address. Anywhere else it is whatever that
/// backend uses to name an object. Either way it is an integer, which is why it
/// can be the one currency the shared code deals in.
extension type const GenAiPtr(int address) {
  static const GenAiPtr nullPtr = GenAiPtr(0);

  bool get isNull => address == 0;
}

/// A failure reported by ONNX Runtime GenAI.
///
/// Declared here rather than beside the FFI calls, because code above the
/// boundary catches it and must not import anything native to do so.
final class GenAiException implements Exception {
  GenAiException(this.message);

  final String message;

  @override
  String toString() => 'GenAiException: $message';
}

/// Thrown where GenAI has no build at all.
///
/// Upstream publishes no WebAssembly library, so the web backend answers every
/// call with this. The package still compiles into a web application, which is
/// the point: an application that uses GenAI on native and something else on
/// the web should not fail to build.
final class GenAiUnsupported implements Exception {
  const GenAiUnsupported(this.operation);

  final String operation;

  @override
  String toString() =>
      'GenAiUnsupported: $operation is not available on this platform. ONNX '
      'Runtime GenAI publishes no WebAssembly build, so there is nothing for '
      'the web backend to call.';
}

/// A handle that has to be released, and refuses use once it has been.
///
/// Above the boundary, so it names no pointer type. The same contract as the
/// base package: release is explicit, because a finalizer does not run in time
/// to matter and cannot be relied on to run at all. Using a released handle is
/// a [StateError] rather than a crash.
abstract base class GenAiHandle {
  GenAiHandle(this._handle);

  GenAiPtr? _handle;

  /// The live handle, or a [StateError] if it has been released.
  GenAiPtr get handle {
    final live = _handle;
    if (live == null) {
      throw StateError(
        '$runtimeType has been released. Values read from it before that stay '
        'valid; the handle itself does not.',
      );
    }
    return live;
  }

  /// Whether this still owns something.
  bool get isReleased => _handle == null;

  /// Releases the native object. Calling twice is an error, not a no-op: a
  /// double release is a bug worth hearing about rather than absorbing.
  void release() {
    destroy(handle);
    _handle = null;
  }

  /// How this particular handle is freed. Generated per type.
  void destroy(GenAiPtr handle);
}

/// Where the generator's inputs live.
///
/// Resolved from the workspace root rather than the working directory. The
/// generator runs from the package, but the test that checks its output runs
/// wherever `dart test` was invoked, and in CI that is the repository root.
library;

import 'dart:io';

/// The pinned ONNX Runtime headers, which are the source of truth for names,
/// parameter direction and ownership.
String get ortHeader => _fromRoot(
      'third_party/onnxruntime/include/onnxruntime/core/session/'
      'onnxruntime_c_api.h',
    );

/// On-device training, declared in its own header and compiled only into the
/// `full` build. The generator reads it the same way as the main one: it is
/// another struct of function pointers.
String get ortTrainingHeader => _fromRoot(
      'third_party/onnxruntime/orttraining/orttraining/training_api/include/'
      'onnxruntime_training_c_api.h',
    );

/// The WebAssembly build's own API, which is a different shape: free functions
/// marked EMSCRIPTEN_KEEPALIVE rather than a struct of function pointers, and
/// a smaller surface than the C API. Generated the same way and for the same
/// reason, so neither backend is hand-written.
String get ortWasmHeader =>
    _fromRoot('third_party/onnxruntime/onnxruntime/wasm/api.h');

/// The ffigen bindings, which are the source of truth for FFI types.
String get ortBindings =>
    _fromRoot('packages/onnxruntime_dart/lib/src/bindings/ort_bindings.g.dart');

String _fromRoot(String relative) => '${_root.path}/$relative';

final Directory _root = _findRoot();

/// Walks up for the workspace root, so neither the generator nor its test
/// depends on where it was run from.
Directory _findRoot() {
  for (var directory = Directory.current;; directory = directory.parent) {
    final pubspec = File('${directory.path}/pubspec.yaml');
    if (pubspec.existsSync() &&
        pubspec
            .readAsStringSync()
            .contains(RegExp(r'^workspace:', multiLine: true))) {
      return directory;
    }
    if (directory.parent.path == directory.path) {
      throw StateError(
        'no workspace root above ${Directory.current.path}: expected a '
        'pubspec.yaml with a workspace: section',
      );
    }
  }
}

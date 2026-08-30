/// Resolves paths against the workspace root.
///
/// Tests reach outside the package for the ONNX Runtime submodule and for
/// locally built binaries, both of which are shared by every package in the
/// workspace. Resolving from the root keeps them working whether `dart test`
/// runs here or at the top.
library;

import 'dart:io';

/// Path under the workspace root.
String fromRoot(String relative) => '${_root.path}/$relative';

/// Path under this package, which is not the working directory when tests run
/// from the workspace root.
String fromPackage(String relative) =>
    fromRoot('packages/onnxruntime_dart/$relative');

final Directory _root = _findRoot();

Directory _findRoot() {
  for (var dir = Directory.current;; dir = dir.parent) {
    final pubspec = File('${dir.path}/pubspec.yaml');
    if (pubspec.existsSync() &&
        pubspec
            .readAsStringSync()
            .contains(RegExp(r'^workspace:', multiLine: true))) {
      return dir;
    }
    if (dir.parent.path == dir.path) {
      throw StateError(
        'no workspace root above ${Directory.current.path}. Expected a '
        'pubspec.yaml declaring workspace: members.',
      );
    }
  }
}

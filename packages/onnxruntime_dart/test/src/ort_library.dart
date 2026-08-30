/// Locates an ONNX Runtime shared library for tests that call into it.
library;

import 'dart:ffi';
import 'dart:io';

import 'paths.dart';

/// Explicit override, set by CI once we build our own binaries.
const _envVar = 'ONNXRUNTIME_LIB';

/// Where a developer build lands. Gitignored.
final _localDir = fromRoot('.local/ort');

String get _libraryName => switch (Platform.operatingSystem) {
      'windows' => 'onnxruntime.dll',
      'macos' => 'libonnxruntime.dylib',
      _ => 'libonnxruntime.so',
    };

/// Path to a runtime library, or null if none is available.
String? findOrtLibrary() {
  final override = Platform.environment[_envVar];
  if (override != null && File(override).existsSync()) return override;

  final local = Directory(_localDir);
  if (!local.existsSync()) return null;
  for (final entry in local.listSync().whereType<Directory>()) {
    final candidate = File('${entry.path}/lib/$_libraryName');
    if (candidate.existsSync()) return candidate.path;
  }
  return null;
}

/// Opens the runtime, or throws if none is available.
DynamicLibrary openOrtLibrary() {
  final path = findOrtLibrary();
  if (path == null) {
    throw StateError(
      'no ONNX Runtime library found. Set $_envVar, or extract a release '
      'under $_localDir/<name>/lib/$_libraryName',
    );
  }
  return DynamicLibrary.open(path);
}

/// Reason to skip, or null when a library is available.
String? get skipWithoutOrt => findOrtLibrary() == null
    ? 'no ONNX Runtime library ($_envVar unset)'
    : null;

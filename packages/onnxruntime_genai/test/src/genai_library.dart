/// Whether these tests have a GenAI library to call into.
///
/// The same shape as the base package's `ort_library.dart`, and for the same
/// reason: a suite that cannot find its library must say so rather than fail
/// with a symbol lookup nobody can read.
library;

import 'dart:io';

/// Explicit override, set by CI once the libraries are staged.
const _envVar = 'ONNXRUNTIME_GENAI_LIB';

/// Where a developer build lands. Gitignored.
String get _localDir {
  var dir = Directory.current;
  while (dir.path != dir.parent.path) {
    final candidate = Directory('${dir.path}/.local/genai');
    if (candidate.existsSync()) return candidate.path;
    dir = dir.parent;
  }
  return '';
}

String get _libraryName => switch (Platform.operatingSystem) {
      'windows' => 'onnxruntime-genai.dll',
      'macos' => 'libonnxruntime-genai.dylib',
      _ => 'libonnxruntime-genai.so',
    };

/// Path to a GenAI library, or null if none is available.
String? findGenAiLibrary() {
  final override = Platform.environment[_envVar];
  if (override != null && File(override).existsSync()) return override;

  final root = _localDir;
  if (root.isEmpty) return null;
  final directory = Directory(root);
  if (!directory.existsSync()) return null;

  for (final entry in directory.listSync(recursive: true).whereType<File>()) {
    if (entry.path.endsWith(_libraryName)) return entry.path;
  }
  return null;
}

/// Why the calling tests are being skipped, or null when they can run.
///
/// Named rather than silent. A skip that does not say what is missing reads
/// the same as one that passed by testing nothing.
String? get skipWithoutGenAi => findGenAiLibrary() == null
    ? 'no GenAI library: set $_envVar, or stage one under .local/genai'
    : null;

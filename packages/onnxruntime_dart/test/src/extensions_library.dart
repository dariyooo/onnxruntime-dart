/// Locating the onnxruntime-extensions library for tests that load it.
///
/// The package installs it as a code asset, but the test suite does not depend
/// on that package: it would pull a native asset into every unrelated test. CI
/// puts the built library where this can find it instead.
library;

import 'dart:io';

import 'paths.dart';

/// Set by CI after downloading the extensions build.
const _envVar = 'ONNXRUNTIME_EXTENSIONS_LIB';

String get _libraryName => switch (Platform.operatingSystem) {
      'windows' => 'ortextensions.dll',
      'macos' => 'libortextensions.dylib',
      _ => 'libortextensions.so',
    };

/// Path to the operator library, or null if none is available.
String? findExtensionsLibrary() {
  final override = Platform.environment[_envVar];
  if (override != null && File(override).existsSync()) return override;

  final local = File(fromRoot('.local/ort-extensions/$_libraryName'));
  return local.existsSync() ? local.path : null;
}

/// Reason to skip, or null when the library is available.
String? get skipWithoutExtensions => findExtensionsLibrary() == null
    ? 'no onnxruntime-extensions library ($_envVar unset)'
    : null;

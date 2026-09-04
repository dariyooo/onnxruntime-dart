/// Shared code must not reach for anything native.
///
/// One `dart:ffi` import anywhere above the backend boundary breaks the whole
/// package on the web, and the failure appears at compile time in a consumer's
/// build rather than here. The same rule the base package holds itself to, and
/// it matters as much for GenAI: upstream publishes no WebAssembly build, so
/// the web backend refuses every call, but an application that uses GenAI on
/// native and something else on the web still has to be able to compile.
@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

/// Directories whose contents are above the boundary.
const _shared = ['lib/src/api', 'lib'];

/// The only files allowed to name something native.
const _native = {
  'lib/native.dart',
  'lib/src/backend/ffi_calls.dart',
  'lib/src/backend/ffi_support.dart',
};

void main() {
  test('the package root points at the seam, not at a backend', () {
    final calls = File('lib/src/backend/calls.dart').readAsStringSync();
    expect(
      calls,
      contains("if (dart.library.js_interop)"),
      reason: 'the backend has to be chosen at compile time, or a web build '
          'pulls in the native one',
    );
  });

  for (final directory in _shared) {
    final root = Directory(directory);
    if (!root.existsSync()) continue;

    for (final file in root.listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      final path = file.path.replaceAll(r'\', '/');
      if (_native.contains(path)) continue;
      if (path.startsWith('lib/src/backend/')) continue;
      if (path.startsWith('lib/src/bindings/')) continue;

      test('shared code $path imports nothing native', () {
        final source = file.readAsStringSync();
        expect(source, isNot(contains("import 'dart:ffi'")), reason: path);
        expect(source, isNot(contains('package:ffi/ffi.dart')), reason: path);
      });
    }
  }
}

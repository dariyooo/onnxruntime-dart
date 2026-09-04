/// Shared code must not reach for anything native.
///
/// One `dart:ffi` import anywhere above the backend boundary breaks the whole
/// package on the web, and the failure appears at compile time in a consumer's
/// build rather than here. This test runs on the web too, so a violation cannot
/// hide behind a VM-only run.
@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

import 'src/paths.dart';

/// The files allowed to reach for `dart:ffi`.
///
/// Listed rather than derived, and everything else in `lib/` is shared by
/// default. That way a new file is covered without anyone remembering to add
/// it, and making one native is a deliberate edit here.
const _nativeOnly = [
  'lib/native.dart',
  'lib/src/ffi/',
  // Not all of lib/src/bindings: config_keys.g.dart is generated constants
  // with no imports at all, and the shared library exports it.
  'lib/src/bindings/ort_bindings.g.dart',
  'lib/src/bindings/api/',
  'lib/src/backend/ffi_calls.dart',
  // The generated native half of the seam. Its web twin,
  // raw_wasm_calls.g.dart, is shared and must stay so.
  'lib/src/backend/raw_ffi_calls.g.dart',
];

bool _isNative(String path) => _nativeOnly.any(path.startsWith);

/// The one sanctioned bridge: a conditional export picking a backend, which is
/// resolved at compile time so neither side is loaded on the other's platform.
const _bridge = 'lib/src/backend/calls.dart';

/// Every Dart file under `lib/`, as a package-relative path with forward
/// slashes.
///
/// Derived by stripping the directory we were handed rather than by splitting
/// on a separator: Windows accepts both, and `fromPackage` returns forward
/// slashes there, so looking for the platform separator finds nothing and every
/// path comes back absolute.
List<String> _libraryFiles() {
  final base = fromPackage('lib');
  return [
    for (final file
        in Directory(base).listSync(recursive: true).whereType<File>())
      if (file.path.endsWith('.dart'))
        'lib/${file.path.substring(base.length + 1).replaceAll(r'\', '/')}',
  ]..sort();
}

Iterable<String> _importsOf(String path) sync* {
  final source = File(fromPackage(path)).readAsStringSync();
  // Import directives only. A doc comment mentioning dart:ffi is fine, and
  // matching plain text would flag the comment explaining this rule.
  for (final match in RegExp(
    r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''',
    multiLine: true,
  ).allMatches(source)) {
    yield match.group(1)!;
  }
}

void main() {
  final shared = _libraryFiles().where((p) => !_isNative(p)).toList();

  group('shared code', () {
    for (final path in shared) {
      test('$path imports nothing native', () {
        final imports = _importsOf(path);

        expect(
          imports.where((i) => i == 'dart:ffi' || i.startsWith('package:ffi')),
          isEmpty,
          reason: '$path must compile for the web. Move anything needing '
              'dart:ffi below the backend boundary.',
        );

        // Reaching a native file transitively is the same breakage, one step
        // removed. Only the backend bridge may, and only conditionally.
        if (path == _bridge) return;
        expect(
          imports.where((i) => _isNative(_resolve(path, i))),
          isEmpty,
          reason: '$path pulls in native code. Reach it through $_bridge.',
        );
      });
    }

    test('paths are package-relative on every platform', () {
      // Windows accepts both separators, so a path built by splitting on the
      // platform's own can come back absolute and match nothing.
      for (final path in _libraryFiles()) {
        expect(path, startsWith('lib/'), reason: path);
        expect(path, isNot(contains(r'\')), reason: path);
        expect(path, isNot(contains(':')), reason: path);
      }
    });

    test('the sweep found the files it is meant to check', () {
      // A rule that checks nothing passes forever.
      expect(shared, contains('lib/onnxruntime_dart.dart'));
      expect(shared, contains('lib/src/session.dart'));
      expect(shared, contains('lib/src/handle.dart'));
      expect(shared.length, greaterThan(5));
    });

    test('imports are actually being found', () {
      // Guards the regex: if it matched nothing, every file above would pass.
      expect(_importsOf('lib/src/backend/interface.dart'), isNotEmpty);
    });
  });

  group('native code', () {
    test('is honest about being native', () {
      // The counterpart: a file listed as native that reaches for nothing
      // native has probably moved layer, and the list is now wrong.
      for (final path in _libraryFiles().where(_isNative)) {
        expect(
          _importsOf(path).any(
            (i) =>
                i == 'dart:ffi' ||
                i.startsWith('package:ffi') ||
                _isNative(_resolve(path, i)),
          ),
          isTrue,
          reason: '$path is treated as native but imports nothing native',
        );
      }
    });
  });
}

/// Resolves a relative import against the importing file, so it can be
/// compared with the native list. Package and dart: imports pass through.
String _resolve(String from, String import) {
  if (import.startsWith('dart:')) return import;
  if (import.startsWith('package:onnxruntime_dart/')) {
    return 'lib/${import.substring('package:onnxruntime_dart/'.length)}';
  }
  if (import.startsWith('package:')) return import;

  final directory = from.substring(0, from.lastIndexOf('/'));
  final parts = <String>[...directory.split('/'), ...import.split('/')];
  final resolved = <String>[];
  for (final part in parts) {
    if (part == '.') continue;
    if (part == '..') {
      if (resolved.isNotEmpty) resolved.removeLast();
      continue;
    }
    resolved.add(part);
  }
  return resolved.join('/');
}

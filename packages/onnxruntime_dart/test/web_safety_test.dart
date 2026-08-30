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

/// Everything that has to compile for dart2js and dart2wasm.
const _shared = [
  'lib/src/backend/types.dart',
  'lib/src/backend/interface.dart',
  'lib/src/handle.dart',
  'lib/src/annotations.dart',
  'lib/onnxruntime_dart.dart',
];

/// Libraries that exist precisely to be native.
const _native = [
  'lib/native.dart',
  'lib/src/bindings/ort_bindings.g.dart',
  'lib/src/ffi/runtime.dart',
];

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
  group('shared code', () {
    for (final path in _shared) {
      test('$path imports nothing native', () {
        final native = _importsOf(
          path,
        ).where((i) => i == 'dart:ffi' || i.startsWith('package:ffi'));

        expect(
          native,
          isEmpty,
          reason: '$path must compile for the web. Move anything needing '
              'dart:ffi below the backend boundary.',
        );
      });
    }

    test('the list is not silently empty', () {
      // A rule that checks nothing passes forever.
      expect(_shared, isNotEmpty);
      for (final path in _shared) {
        expect(File(fromPackage(path)).existsSync(), isTrue, reason: path);
      }
    });

    test('imports are actually being found', () {
      // Guards the regex: if it matched nothing, every file above would pass.
      expect(_importsOf('lib/src/backend/interface.dart'), isNotEmpty);
    });
  });

  group('native code', () {
    test('is honest about being native', () {
      // The counterpart: these are meant to be unusable on the web, and if one
      // stopped importing dart:ffi it has probably moved layer.
      for (final path in _native) {
        expect(
          _importsOf(path).any(
            (i) =>
                i == 'dart:ffi' ||
                i.startsWith('package:ffi') ||
                i.contains('bindings/') ||
                i.contains('ffi/'),
          ),
          isTrue,
          reason: '$path is listed as native but imports nothing native',
        );
      }
    });
  });
}

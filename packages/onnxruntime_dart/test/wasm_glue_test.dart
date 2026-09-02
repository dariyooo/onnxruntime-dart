@TestOn('vm')

/// The JavaScript this package binds by hand still exists upstream.
///
/// The WebAssembly backend is generated from `wasm/api.h`, and
/// `seam_table_test.dart` keeps that honest. The JavaScript side is not, and
/// cannot be: `asyncInit`, `webnnInit` and the rest are assignments onto
/// `Module` in ONNX Runtime's glue scripts, which appear in no header. They are
/// written out by hand in `backend/wasm/`, so this is what notices when
/// upstream renames or drops one. Without it the failure is at run time in a
/// browser, as a missing method on an object.
library;

import 'dart:io';

import 'package:test/test.dart';

import 'src/paths.dart';

/// Names Emscripten provides, not ONNX Runtime.
///
/// Part of the Emscripten runtime rather than anything upstream chose, so
/// there is no ONNX Runtime source to check them against.
const _emscripten = {
  'HEAPU8',
  'UTF8ToString',
  'lengthBytesUTF8',
  'stringToUTF8',
  '_malloc',
  '_free',
};

/// Names that are not the module at all.
const _notTheModule = {'navigator'};

/// Every `@JS('...')` in the WebAssembly backend that was written by hand.
Set<String> _handWritten() {
  final directory = Directory(fromPackage('lib/src/backend/wasm'));
  final names = <String>{};

  for (final file in directory.listSync().whereType<File>()) {
    if (file.path.endsWith('.g.dart')) continue;
    for (final match
        in RegExp(r"@JS\('([^']+)'\)").allMatches(file.readAsStringSync())) {
      names.add(match.group(1)!);
    }
  }
  return names;
}

void main() {
  late final Set<String> bound;
  late final String glue;
  late final String header;
  late final String webnnProvider;

  setUpAll(() {
    bound = _handWritten();

    glue = Directory(fromRoot('third_party/onnxruntime/onnxruntime/wasm'))
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.js'))
        .map((file) => file.readAsStringSync())
        .join('\n');

    header = File(
      fromRoot('third_party/onnxruntime/onnxruntime/wasm/api.h'),
    ).readAsStringSync();

    webnnProvider = File(
      fromRoot(
        'third_party/onnxruntime/onnxruntime/core/providers/webnn/'
        'webnn_execution_provider.cc',
      ),
    ).readAsStringSync();
  });

  test('there is something to check', () {
    expect(bound, isNotEmpty);
    expect(glue.length, greaterThan(1000));
  });

  test('every exported C function bound by hand is in the header', () {
    // Underscore-prefixed names are Emscripten's spelling of a C export, so
    // the name upstream declares is the same one without it.
    final exports = bound.where((name) => name.startsWith('_Ort'));
    expect(exports, isNotEmpty);

    for (final name in exports) {
      expect(
        header,
        contains(name.substring(1)),
        reason: '$name is bound in backend/wasm but wasm/api.h no longer '
            'declares ${name.substring(1)}',
      );
    }
  });

  test('every module property bound by hand is still set by the glue', () {
    final properties = bound
        .where((name) => !name.startsWith('_'))
        .where((name) => !_emscripten.contains(name))
        .where((name) => !_notTheModule.contains(name))
        // Set by this package for the provider to read, so the glue never
        // assigns it. Checked against the code that reads it instead.
        .where((name) => name != 'currentContext');

    expect(properties, isNotEmpty);

    for (final name in properties) {
      expect(
        glue,
        anyOf(contains('Module["$name"]'), contains('Module.$name')),
        reason: '$name is bound in backend/wasm but no script in '
            'onnxruntime/wasm assigns it any more',
      );
    }
  });

  test('the property the WebNN provider reads is the one we set', () {
    // The whole handshake rests on this string matching on both sides, and
    // neither side would fail to compile if it stopped.
    expect(bound, contains('currentContext'));
    expect(
      webnnProvider,
      contains('module_property("currentContext")'),
      reason: 'the WebNN provider no longer reads currentContext, so '
          'backend/wasm/webnn.dart is setting something nothing looks at',
    );
  });
}

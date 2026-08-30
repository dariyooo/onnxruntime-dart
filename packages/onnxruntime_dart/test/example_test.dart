@TestOn('vm')
@Tags(['exclusive'])

/// Runs the examples rather than duplicating them.
///
/// They live in `example/` and import through `package:`, so they read like a
/// consumer's code. Executing them is the only link that cannot rot: an example
/// that stops compiling or stops working fails here.
library;

import 'dart:io';

import 'package:test/test.dart';

import 'src/ort_library.dart';
import 'src/paths.dart';

const _model = 'third_party/onnxruntime/onnxruntime/test/testdata/'
    'ort_minimal_e2e_test_data/test_voice_commands/model.onnx';

Future<ProcessResult> _runExample(String name) => Process.run(
    'dart',
    [
      'run',
      fromPackage('example/$name'),
      fromRoot(_model),
    ],
    workingDirectory: fromPackage(''));

void main() {
  group('examples', () {
    test('short_lived_isolate loads a model on a spawned isolate', () async {
      final result = await _runExample('short_lived_isolate.dart');

      expect(result.exitCode, 0, reason: result.stderr.toString());
      // The model's input, read from the model rather than hard-coded here.
      expect(result.stdout, contains('input_1'));
      expect(result.stdout, contains('[1, 6]'));
    });

    test('long_lived_isolate serves many requests from one session', () async {
      final result = await _runExample('long_lived_isolate.dart');

      expect(result.exitCode, 0, reason: result.stderr.toString());
      // Three requests, one session, so the answer is the same each time.
      for (var i = 0; i < 3; i++) {
        expect(result.stdout, contains('request $i: [input_1]'));
      }
    });

    test('every example is exercised', () {
      // An example nobody runs is an example that rots.
      final files = Directory(fromPackage('example'))
          .listSync()
          .whereType<File>()
          .map((f) => f.uri.pathSegments.last)
          .where((n) => n.endsWith('.dart'))
          .toSet();

      expect(files, {'short_lived_isolate.dart', 'long_lived_isolate.dart'});
    });
  }, skip: skipWithoutNativeAsset);
}

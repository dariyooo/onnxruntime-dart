@TestOn('vm')

/// Finding the runtime, and asking it what it can do.
///
/// This package ships no binaries. It declares one `@Native` per runtime
/// package and uses whichever resolves, which is what lets an application pick
/// its runtime by dependency alone.
///
/// It deliberately does not report which package answered. A missing asset
/// falls back to a process-wide symbol lookup, so once anything has loaded the
/// library the other binding resolves too and the answer would be whichever
/// ran first. Capability is asked of the library instead, which is both
/// knowable and the thing callers actually want.
library;

import 'dart:io';

import 'package:onnxruntime_dart/native.dart';
import 'package:test/test.dart';

import 'src/ort_library.dart';
import 'src/paths.dart';

void main() {
  group('the installed runtime', () {
    test('answers calls', () {
      expect(runtimeVersion(), matches(RegExp(r'^\d+\.\d+\.\d+')));
      expect(ortApi(), isNot(equals(0)));
    });

    test('reports whether training was compiled in', () {
      // The workspace installs the base runtime, which ORT documents as
      // returning null from GetTrainingApi rather than failing.
      expect(trainingIsAvailable(), isFalse);
    });
  }, skip: skipWithoutOrt ?? skipWithoutNativeAsset);

  group('when nothing is installed', () {
    test('the error names both packages', () {
      // Not reachable here, so the message is checked directly: it is the
      // first thing anyone sees who forgot to add a runtime.
      expect(
        const OrtRuntimeMissing().toString(),
        allOf(
          contains('onnxruntime_base'),
          contains('onnxruntime_full'),
          contains('ships the bindings but no binaries'),
        ),
      );
    });
  });

  group('the boundary', () {
    test('choosing a runtime is native only', () {
      // Meaningless on the web, where the application serves the .wasm itself.
      // Exporting any of it from the shared library would drag dart:ffi in and
      // break the browser outright.
      final shared =
          File(fromPackage('lib/onnxruntime_dart.dart')).readAsStringSync();
      expect(shared, isNot(contains('OrtRuntimeMissing')));
      expect(shared, isNot(contains('trainingIsAvailable')));
    });

    test('neither runtime package is a real dependency of the bindings', () {
      // A dev dependency gives this package's own tests a library to load. If
      // it became a real one, every application would be handed a runtime it
      // did not choose, and choosing would stop working.
      final pubspec = File(fromPackage('pubspec.yaml')).readAsStringSync();
      final dependencies = pubspec.split('dev_dependencies:').first;
      expect(dependencies, isNot(contains('onnxruntime_base')));
    });
  });
}

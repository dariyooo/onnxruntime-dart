@TestOn('vm')

/// Guards `X.Y.Z+onnxruntime-<ORT version>`.
///
/// Three things must agree and only a test keeps them agreeing: the pubspec
/// version, the pinned submodule, and the `ORT_API_VERSION` the bindings were
/// generated from. Bumping the submodule alone would publish bindings that
/// describe a different ABI than the version claims.
library;

import 'dart:io';

import 'package:test/test.dart';

import 'src/paths.dart';

void main() {
  group('version scheme', () {
    late final String packageVersion =
        _field(fromPackage('pubspec.yaml'), 'version');
    late final String ortVersion =
        File(fromRoot('third_party/onnxruntime/VERSION_NUMBER'))
            .readAsStringSync()
            .trim();

    test('pubspec version carries onnxruntime build metadata', () {
      expect(
        packageVersion,
        matches(RegExp(r'^\d+\.\d+\.\d+\+onnxruntime-\d+\.\d+\.\d+$')),
        reason: 'expected X.Y.Z+onnxruntime-A.B.C, got "$packageVersion"',
      );
    });

    test('build metadata matches the pinned submodule', () {
      final declared = packageVersion.split('+onnxruntime-').last;
      expect(
        declared,
        ortVersion,
        reason: 'pubspec.yaml claims ORT $declared but the submodule at '
            'third_party/onnxruntime is $ortVersion. Bump one or the other.',
      );
    });

    test('bindings were generated from the pinned headers', () {
      final header = File(
        fromRoot('third_party/onnxruntime/include/onnxruntime/core/session/'
            'onnxruntime_c_api.h'),
      ).readAsStringSync();
      final match = RegExp(r'^#define ORT_API_VERSION (\d+)', multiLine: true)
          .firstMatch(header);
      expect(match, isNotNull,
          reason: 'ORT_API_VERSION not found in the header');

      final headerApiVersion = int.parse(match!.group(1)!);
      final bindings = File(fromPackage('lib/src/bindings/ort_bindings.g.dart'))
          .readAsStringSync();
      expect(
        bindings,
        contains('const int ORT_API_VERSION = $headerApiVersion;'),
        reason: 'lib/src/bindings is stale relative to the submodule. '
            'Run `dart run ffigen --config ffigen.yaml`.',
      );

      // ORT's API version tracks its minor version.
      expect(headerApiVersion, int.parse(ortVersion.split('.')[1]));
    });
  });
}

/// Reads a top-level scalar without taking a YAML dependency for one field.
String _field(String path, String key) {
  final pattern = RegExp('^$key:\\s*(\\S+)\\s*\$', multiLine: true);
  final match = pattern.firstMatch(File(path).readAsStringSync());
  if (match == null) throw StateError('no top-level "$key" in $path');
  return match.group(1)!;
}

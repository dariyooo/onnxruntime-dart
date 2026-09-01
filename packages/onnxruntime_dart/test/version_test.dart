@TestOn('vm')

/// Guards the versions against each other.
///
/// Four things must agree and only a test keeps them agreeing: the bindings'
/// `X.Y.Z+onnxruntime-<ORT version>`, the two runtime packages whose whole
/// version is the ONNX Runtime version, the pinned submodule, and the
/// `ORT_API_VERSION` the bindings were generated from.
///
/// The runtime packages matter most: their version is what names the release
/// their build hook downloads from, so a wrong one installs the wrong binaries
/// or none at all.
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

    for (final package in ['onnxruntime_binaries', 'onnxruntime_binaries']) {
      test('$package is versioned as the runtime it installs', () {
        final version =
            _field(fromRoot('packages/$package/pubspec.yaml'), 'version');
        expect(
          version,
          ortVersion,
          reason: '$package claims $version but the submodule is $ortVersion. '
              'That version names the release its hook downloads from, so it '
              'has to be the runtime version exactly.',
        );
      });
    }

    test('both runtime packages install the same runtime', () {
      // Base and full differ in what is compiled in, never in which ONNX
      // Runtime, so an application swapping one for the other keeps its ABI.
      expect(
        _field(
            fromRoot('packages/onnxruntime_binaries/pubspec.yaml'), 'version'),
        _field(
          fromRoot('packages/onnxruntime_binaries/pubspec.yaml'),
          'version',
        ),
      );
    });

    for (final ep in ['webgpu', 'cuda']) {
      test('onnxruntime_ep_$ep is versioned as the plugin it installs', () {
        // ONNX Runtime versions each plugin separately from the runtime and
        // from each other, which is why they are separate packages: they
        // cannot share a version, so they cannot share a pubspec.
        final declared = _field(
          fromRoot('packages/onnxruntime_ep_$ep/pubspec.yaml'),
          'version',
        );
        final upstream = File(
          fromRoot('third_party/onnxruntime/plugin-ep-$ep/VERSION_NUMBER'),
        ).readAsStringSync().trim();

        expect(
          declared,
          upstream,
          reason: 'onnxruntime_ep_$ep says $declared but the pinned tree says '
              '$upstream. That version names the release its hook downloads '
              'from.',
        );
      });
    }

    test('each provider inherits its minimum runtime, not invents it', () {
      // ONNX Runtime compiles each plugin's MIN_ONNXRUNTIME_VERSION into the
      // library and checks it on load. Each provider package keeps a copy so
      // the mismatch can be reported first and better, which is only useful
      // while it agrees with the pinned tree.
      //
      // Read from the packages rather than from a table here: this package
      // deliberately knows about no provider in particular.
      final packages = Directory(fromRoot('packages'))
          .listSync()
          .whereType<Directory>()
          .where((d) => d.path.contains('onnxruntime_ep_'));

      var checked = 0;
      for (final package in packages) {
        final name = package.path
            .split(Platform.pathSeparator)
            .last
            .replaceFirst('onnxruntime_ep_', '');
        final source = File('${package.path}/lib/onnxruntime_ep_$name.dart');
        if (!source.existsSync()) continue;

        final declared = RegExp(r"minimumRuntime = '([^']+)'")
            .firstMatch(source.readAsStringSync())
            ?.group(1);
        expect(declared, isNotNull, reason: '$name declares no minimumRuntime');

        final pinned = File(fromRoot(
            'third_party/onnxruntime/plugin-ep-$name/MIN_ONNXRUNTIME_VERSION'));
        if (!pinned.existsSync()) continue;

        expect(
          declared,
          pinned.readAsStringSync().trim(),
          reason: '$name claims it needs $declared, the pinned tree disagrees',
        );
        checked++;
      }

      expect(checked, greaterThan(0), reason: 'no provider package was read');
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

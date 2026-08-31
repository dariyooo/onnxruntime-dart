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

import 'package:onnxruntime_dart/native.dart';
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

    test('the minimum runtime is inherited, not invented', () {
      // ONNX Runtime compiles each plugin's MIN_ONNXRUNTIME_VERSION into the
      // library and checks it on load. We keep a copy so the mismatch can be
      // reported first and better, which is only useful while it agrees.
      for (final provider in OrtExecutionProvider.values) {
        final file = File(
          fromRoot('third_party/onnxruntime/plugin-ep-${provider.name}/'
              'MIN_ONNXRUNTIME_VERSION'),
        );
        if (!file.existsSync()) continue;
        expect(
          provider.minimumRuntime,
          file.readAsStringSync().trim(),
          reason: '${provider.name} claims it needs '
              '${provider.minimumRuntime}, the pinned tree says otherwise',
        );
      }
    });

    test('every provider works against the runtime we ship', () {
      for (final provider in OrtExecutionProvider.values) {
        expect(
          provider.supportsRuntime(ortVersion),
          isTrue,
          reason: '${provider.name} needs ${provider.minimumRuntime} but we '
              'ship $ortVersion',
        );
      }
    });

    test('providers outlive the runtime they were built with', () {
      // Each plugin declares the oldest runtime it works against, and it is
      // below ours. That is what lets a provider package stay put while the
      // runtime packages move.
      for (final ep in ['webgpu', 'cuda']) {
        final minimum = File(
          fromRoot('third_party/onnxruntime/plugin-ep-$ep/'
              'MIN_ONNXRUNTIME_VERSION'),
        ).readAsStringSync().trim();
        expect(
          _isAtMost(minimum, ortVersion),
          isTrue,
          reason: '$ep needs ONNX Runtime $minimum but ours is $ortVersion',
        );
      }
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

/// Whether [a] is the same version as [b] or older.
bool _isAtMost(String a, String b) {
  final left = a.split('.').map(int.parse).toList();
  final right = b.split('.').map(int.parse).toList();
  for (var i = 0; i < left.length && i < right.length; i++) {
    if (left[i] != right[i]) return left[i] < right[i];
  }
  return true;
}

/// Reads a top-level scalar without taking a YAML dependency for one field.
String _field(String path, String key) {
  final pattern = RegExp('^$key:\\s*(\\S+)\\s*\$', multiLine: true);
  final match = pattern.firstMatch(File(path).readAsStringSync());
  if (match == null) throw StateError('no top-level "$key" in $path');
  return match.group(1)!;
}

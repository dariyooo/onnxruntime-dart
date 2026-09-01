@TestOn('vm')

/// One call site has to compile and run everywhere.
///
/// The promise of the package is that an application writes its inference code
/// once. That holds only if the two bootstraps agree exactly: same name, same
/// parameters, same return. A difference here is a difference every consumer
/// pays for, and it would otherwise only show up when someone builds for the
/// other platform.
library;

import 'dart:io';

import 'package:test/test.dart';

import 'src/paths.dart';

/// The parameters of `openOnnxRuntime` in one bootstrap file.
List<String> _signature(String path) {
  final source = File(path).readAsStringSync();
  final match = RegExp(
    r'Future<void>\s+openOnnxRuntime\(\{(.*?)\}\)',
    dotAll: true,
  ).firstMatch(source);
  expect(match, isNotNull, reason: '$path declares no openOnnxRuntime');

  return match!
      .group(1)!
      .split(',')
      .map((p) => p.trim())
      .where((p) => p.isNotEmpty)
      .toList();
}

void main() {
  final directory = fromPackage('lib/src/api');

  test('both platforms take the same arguments', () {
    expect(
      _signature('$directory/bootstrap_web.dart'),
      _signature('$directory/bootstrap_native.dart'),
      reason: 'openOnnxRuntime must look identical on both platforms, or an '
          'application cannot call it from shared code',
    );
  });

  test('each platform accepts the other platform options and ignores them', () {
    // The alternative is a conditional import in every application, which is
    // the thing this call exists to remove.
    for (final file in ['bootstrap_native.dart', 'bootstrap_web.dart']) {
      final parameters = _signature('$directory/$file');
      expect(parameters.join(' '), contains('WebRuntimeOptions'));
      expect(parameters.join(' '), contains('NativeRuntimeOptions'));
    }
  });

  test('the conditional export names both implementations', () {
    final source = File('$directory/bootstrap.dart').readAsStringSync();
    expect(source, contains("export 'bootstrap_native.dart'"));
    expect(
        source, contains("if (dart.library.js_interop) 'bootstrap_web.dart'"));
  });
}

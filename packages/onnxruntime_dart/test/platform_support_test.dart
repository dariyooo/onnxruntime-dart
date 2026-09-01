@TestOn('vm')

/// The correspondence table has to describe the backends, not just itself.
///
/// `platformSupport` is generated from which header declares each operation.
/// This checks the WebAssembly backend against it: every operation the table
/// says the web cannot do must refuse, and every operation it says the web can
/// do must not. Without this the table would be a comment that compiles.
library;

import 'dart:io';

import 'package:onnxruntime_dart/src/backend/platform_support.g.dart';
import 'package:test/test.dart';

import 'src/paths.dart';

void main() {
  late String backend;
  late Set<String> refused;

  setUpAll(() {
    backend =
        File(fromPackage('lib/src/backend/wasm_calls.dart')).readAsStringSync();

    // A method that hands off to unsupportedOnWeb, by name.
    refused = {
      for (final match in RegExp(
        r'\s(\w+)\([^)]*\)[^;{]*=>\s*unsupportedOnWeb',
        dotAll: true,
      ).allMatches(backend))
        match.group(1)!,
    };
  });

  test('the table is not empty and names real operations', () {
    expect(platformSupport, isNotEmpty);
    expect(platformSupport['createSession']?.native, isTrue);
    expect(platformSupport['createSession']?.web, isTrue);
  });

  test('the web backend refuses what the table says it cannot do', () {
    for (final entry in platformSupport.entries) {
      if (entry.value.web) continue;
      // Only the operations that are actually seam methods; the table also
      // names calls the backends use internally.
      if (!backend.contains('${entry.key}(')) continue;

      expect(
        refused,
        contains(entry.key),
        reason: '${entry.key} is native only, so the web backend has to say '
            'so rather than calling into a function that is not there',
      );
    }
  });

  test('the web backend refuses nothing the table says it can do', () {
    for (final name in refused) {
      final support = platformSupport[name];
      if (support == null) continue;
      expect(
        support.web,
        isFalse,
        reason: '$name refuses on the web, but the table says the '
            'WebAssembly build exports it. One of the two is wrong.',
      );
    }
  });

  test('every refusal explains itself', () {
    // An UnsupportedError with no reason is a dead end for whoever hits it.
    for (final match
        in RegExp(r"unsupportedOnWeb\(\s*'(\w+)',\s*\n?\s*'([^']+)")
            .allMatches(backend)) {
      expect(match.group(2), isNotEmpty, reason: '${match.group(1)}');
      expect(
        match.group(2)!.length,
        greaterThan(20),
        reason: '${match.group(1)} refuses without saying why',
      );
    }
  });
}

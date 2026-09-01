@TestOn('vm')

/// The one hand-written link between the two generated backends.
///
/// Both binding layers come from pinned headers, but nothing in either header
/// says which functions are the same operation. That correspondence is written
/// down in tool/src/seam.dart, and this is what stops it from being trusted:
/// an upstream rename fails here with the name rather than silently leaving a
/// backend pointing at a function that no longer exists.
library;

import 'dart:io';

import 'package:test/test.dart';

import '../tool/src/paths.dart';
import '../tool/src/seam.dart';
import '../tool/src/wasm_api.dart';

void main() {
  late Set<String> nativeNames;
  late Set<String> wasmNames;

  setUpAll(() {
    // Every C function, from the ffigen output rather than the wrappers: the
    // table maps to the C API, and whether a call also got a wrapper is a
    // separate question. GetVersionString lives on OrtApiBase and has none.
    nativeNames = {
      ...RegExp(r'>\s+(\w+);')
          .allMatches(File(ortBindings).readAsStringSync())
          .map((m) => m.group(1)!),
    };

    wasmNames = {
      for (final function
          in parseWasmApi(File(ortWasmHeader).readAsStringSync()))
        function.name,
    };
  });

  test('both headers were read', () {
    expect(nativeNames, hasLength(greaterThan(400)));
    expect(wasmNames, hasLength(greaterThan(30)));
  });

  test('every name the table claims still exists upstream', () {
    expect(verify(nativeNames: nativeNames, wasmNames: wasmNames), isEmpty);
  });

  test('the rule matches most of the WebAssembly surface on its own', () {
    // If this drops sharply, the rule stopped working and the table is about
    // to absorb the difference one hand-written entry at a time.
    final matched = wasmNames
        .where((name) => autoMatched(name, nativeNames) != null)
        .length;
    expect(matched, greaterThan(wasmNames.length ~/ 2));
  });

  test('availability follows from the table, not from an annotation', () {
    for (final operation in correspondence) {
      expect(
        [operation.isPortable, operation.isNativeOnly, operation.isWebOnly]
            .where((yes) => yes)
            .length,
        1,
        reason: '${operation.name} must be exactly one of portable, native '
            'only or web only',
      );
    }
  });

  test('an operation on neither side is meaningless', () {
    for (final operation in correspondence) {
      expect(
        operation.native ?? operation.wasm,
        isNotNull,
        reason: '${operation.name} names no function on either side',
      );
    }
  });
}

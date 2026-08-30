@TestOn('vm')

/// The generator, checked against what it produced.
///
/// The wrappers are committed, so nothing at runtime would notice if the
/// generator and its output drifted apart. Re-running it here and comparing is
/// what keeps the committed files honest.
library;

import 'dart:io';

import 'package:test/test.dart';

import '../tool/src/c_api.dart';
import '../tool/src/emit.dart';
import '../tool/src/ffigen_api.dart';
import '../tool/src/generate.dart';
import '../tool/src/types.dart';
import 'src/paths.dart';

void main() {
  final header = File(
    fromRoot(
      'third_party/onnxruntime/include/onnxruntime/core/session/'
      'onnxruntime_c_api.h',
    ),
  );
  final bindings = File(fromPackage('lib/src/bindings/ort_bindings.g.dart'));

  group('output', () {
    late final Generated generated;

    setUpAll(() => generated = generate(header: header, bindings: bindings));

    test('matches what is checked in', () {
      for (final entry in generated.files.entries) {
        final file = File(fromPackage('lib/src/bindings/api/${entry.key}'));
        expect(
          file.existsSync(),
          isTrue,
          reason: '${entry.key} is missing. '
              'Run `dart run tool/generate_bindings.dart`.',
        );
        expect(
          file.readAsStringSync(),
          entry.value,
          reason: '${entry.key} is stale. '
              'Run `dart run tool/generate_bindings.dart`.',
        );
      }
    });

    test('leaves nothing generated behind', () {
      final onDisk = Directory(fromPackage('lib/src/bindings/api'))
          .listSync()
          .whereType<File>()
          .map((f) => f.uri.pathSegments.last)
          .where((n) => n.endsWith('.g.dart'))
          .toSet();
      expect(
        onDisk.difference(generated.files.keys.toSet()),
        isEmpty,
        reason: 'orphaned files the generator no longer produces',
      );
    });
  });

  group('parsing', () {
    late final Map<String, List<CFunction>> apis;
    late final Map<String, Map<String, Signature>> signatures;

    setUpAll(() {
      apis = parseApis(header.readAsStringSync());
      signatures = readApiSignatures(bindings);
    });

    test('attributes each function to the struct that declares it', () {
      // These live on sibling tables reached through their own getters. Putting
      // them on OrtApi compiles until the member is looked up.
      expect(apis['OrtModelEditorApi']?.map((f) => f.name),
          contains('CreateSessionFromModel'));
      expect(apis['OrtApi']?.map((f) => f.name),
          isNot(contains('CreateSessionFromModel')));
    });

    test('reads the same members ffigen emitted', () {
      for (final api in apis.entries) {
        final members = signatures[api.key];
        if (members == null) continue;
        for (final function in api.value) {
          final signature = members[function.name];
          if (signature == null) continue;
          expect(
            signature.length,
            function.parameters.length,
            reason: '${api.key}.${function.name} parses with a different '
                'parameter count than ffigen emitted',
          );
        }
      }
    });

    test('reads release functions, which return void', () {
      final release = apis['OrtApi']!.firstWhere((f) => f.name == 'ReleaseEnv');
      expect(release.returnsStatus, isFalse);
      expect(release.parameters.single.type, 'OrtEnv*');
    });

    test('reads SAL direction', () {
      final get =
          apis['OrtApi']!.firstWhere((f) => f.name == 'SessionGetInputCount');
      expect(get.inputs.map((p) => p.name), ['session']);
      expect(get.outputs.map((p) => p.name), ['out']);
    });
  });

  group('type mapping', () {
    CParameter parameter(String type, Direction direction) =>
        CParameter(name: 'x', type: type, direction: direction);

    test('an out-parameter leaves the parameter list', () {
      expect(map(parameter('size_t*', Direction.output)), isA<OutputMapping>());
      expect(map(parameter('size_t', Direction.input)), isA<InputMapping>());
    });

    test('scalars take their Dart type from the signature, not the header', () {
      // Two C enums of the same shape can land on Int and UnsignedInt, so the
      // header cannot be the one deciding.
      expect(
        (map(parameter('size_t', Direction.input)) as InputMapping).dartType,
        isNull,
      );
      expect(
        (map(parameter('int*', Direction.output)) as OutputMapping).dartType,
        isNull,
      );
    });

    test('allocator strings are freed, runtime strings are not', () {
      final owned = map(parameter('char**', Direction.output));
      final borrowed = map(parameter('const char**', Direction.output));
      expect(
          (owned as OutputMapping).read('p'), contains('takeAllocatedString'));
      expect((borrowed as OutputMapping).read('p'), contains('toDartString'));
    });

    test('paths marshal through the ORTCHAR_T helper', () {
      final path = map(parameter('const ORTCHAR_T*', Direction.input));
      expect((path as InputMapping).marshal('p'), 'allocateOrtPath(p, arena)');
    });

    test('what it cannot map says so', () {
      expect(map(parameter('OrtLoggingFunction', Direction.input)),
          isA<Unmapped>());
    });
  });

  group('emitting', () {
    test('qualifies member access', () {
      // package:ffi exports an extension named AllocatorAlloc, which shadows
      // the struct member of the same name.
      final code = emit(
        CFunction(
          name: 'AllocatorAlloc',
          parameters: [
            CParameter(
              name: 'allocator',
              type: 'OrtAllocator*',
              direction: Direction.input,
            ),
          ],
        ),
        ['Pointer<OrtAllocator>'],
      );
      expect(code, contains('this.AllocatorAlloc'));
    });

    test('refuses a signature that disagrees with the header', () {
      final code = emit(
        CFunction(
          name: 'Whatever',
          parameters: [
            CParameter(
              name: 'a',
              type: 'OrtEnv*',
              direction: Direction.input,
            ),
          ],
        ),
        ['Pointer<OrtEnv>', 'Size'],
      );
      expect(code, isNull);
    });
  });
}

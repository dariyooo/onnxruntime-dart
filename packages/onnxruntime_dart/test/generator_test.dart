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

    test('wraps every function it can map', () {
      // Grouping decides which file a wrapper lands in. It once decided
      // whether one was emitted at all, which silently dropped 165 functions.
      final apis = parseApis(header.readAsStringSync());
      final signatures = readApiSignatures(bindings);
      final emitted = generated.files.values
          .expand((source) => RegExp(r'/// `(\w+)`').allMatches(source))
          .map((m) => m.group(1))
          .toSet();

      for (final api in apis.entries) {
        final members = signatures[api.key];
        if (members == null) continue;
        for (final function in api.value) {
          if (members[function.name] == null) continue;
          if (!isFullyMapped(function)) continue;
          expect(
            emitted,
            contains(function.name),
            reason: '${api.key}.${function.name} maps but was not emitted',
          );
        }
      }
    });

    test('every function is either wrapped or explained', () {
      final apis = parseApis(header.readAsStringSync());
      final total = apis.entries
          .where((e) => readApiSignatures(bindings).containsKey(e.key))
          .fold(0, (n, e) => n + e.value.length);
      expect(generated.wrappers + generated.skipped.length, total);
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
      // char** with an allocator is memory the caller must return. const
      // char** is borrowed from the object and freeing it would be a fault.
      final owned = map(parameter('char**', Direction.output)) as OutputMapping;
      final borrowed =
          map(parameter('const char**', Direction.output)) as OutputMapping;

      expect(owned.read('p'), contains('takeAllocatedString'));
      expect(owned.needsAllocator, isTrue);
      expect(borrowed.read('p'), contains('toDartString'));
      expect(borrowed.needsAllocator, isFalse);
    });

    test('paths marshal through the ORTCHAR_T helper', () {
      final path = map(parameter('const ORTCHAR_T*', Direction.input));
      expect((path as InputMapping).marshal('p'), 'allocateOrtPath(p, arena)');
    });

    test('what it cannot map says so', () {
      expect(map(parameter('OrtLoggingFunction', Direction.input)),
          isA<Unmapped>());
    });

    test('an inout scalar pointer is refused rather than copied', () {
      // UseCooIndices takes a buffer the runtime keeps: the header says its
      // life span must eclipse the tensor's. Marshalling it into a call-scoped
      // arena compiles, runs, and leaves the tensor pointing at freed memory.
      expect(
        map(parameter('int64_t*', Direction.inout)),
        isA<Unmapped>(),
      );
      expect(
        map(parameter('size_t*', Direction.inout)),
        isA<Unmapped>(),
      );
    });

    test('an inout handle is still an ordinary input', () {
      // Most inout parameters are handles the call mutates in place, which is
      // the common case and must keep working.
      expect(
        map(parameter('OrtSessionOptions*', Direction.inout)),
        isA<InputMapping>(),
      );
      expect(
        map(parameter('void*', Direction.inout)),
        isA<InputMapping>(),
      );
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

    test('warns where the runtime keeps a caller buffer', () {
      // The signature cannot say it and the SAL does not mark it, so silence
      // is what makes passing a short-lived pointer easy.
      final code = emit(
        CFunction(
          name: 'CreateTensorWithDataAsOrtValue',
          parameters: [
            CParameter(
              name: 'p_data',
              type: 'void*',
              direction: Direction.input,
            ),
          ],
        ),
        ['Pointer<Void>'],
      );
      expect(code, contains('Borrows, does not copy'));
      expect(code, contains('must outlive'));
    });

    test('frees with the allocator the call was given', () {
      // Freeing with the default allocator when the caller passed another is
      // a mismatched free, and it works right up until someone passes one.
      final code = emit(
        CFunction(
          name: 'SessionGetInputName',
          parameters: [
            CParameter(
              name: 'allocator',
              type: 'OrtAllocator*',
              direction: Direction.inout,
            ),
            CParameter(
              name: 'value',
              type: 'char**',
              direction: Direction.output,
            ),
          ],
        ),
        ['Pointer<OrtAllocator>', 'Pointer<Pointer<Char>>'],
      );
      expect(code, contains('takeAllocatedString(out0, allocator)'));
    });

    test('the warnings name functions that exist', () {
      final names = {
        for (final api in parseApis(header.readAsStringSync()).values)
          for (final function in api) function.name,
      };
      for (final name in retainedBuffers.keys) {
        expect(names, contains(name),
            reason: '$name is no longer in the C API');
      }
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

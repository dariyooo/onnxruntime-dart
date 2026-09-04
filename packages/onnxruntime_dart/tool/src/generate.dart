/// Produces the generated wrapper files, without writing anything.
///
/// Kept separate from the command so a test can re-run the generator and
/// compare against what is checked in, which is what makes the committed output
/// verifiable rather than merely plausible.
library;

import 'dart:io';

import 'package:dart_style/dart_style.dart';
import 'package:pub_semver/pub_semver.dart';

import 'c_api.dart';
import 'emit.dart';
import 'ffigen_api.dart';
import 'paths.dart';
import 'types.dart';
import 'raw_seam.dart';
import 'seam.dart';
import 'wasm_api.dart';

/// The generator's output: files to write, and what it could not handle.
final class Generated {
  const Generated({
    required this.files,
    required this.skipped,
    required this.wrappers,
  });

  /// File name to contents, relative to the output directory.
  final Map<String, String> files;

  /// One line per function left out, with the type that defeated it.
  final List<String> skipped;

  /// How many functions were wrapped.
  final int wrappers;
}

/// Formats to the same style as the rest of the package, so what the generator
/// writes needs no follow-up pass and can be compared byte for byte.
final _formatter = DartFormatter(languageVersion: Version(3, 6, 0));

/// Generates from the pinned sources.
///
/// The one definition of what the generator reads, so the command and the test
/// that checks its output cannot disagree about the inputs. They did once: a
/// header added to the command alone made the test call the new files orphans.
Generated generateFromPinnedSources() => generate(
      header: File(ortHeader),
      bindings: File(ortBindings),
      extraHeaders: [File(ortTrainingHeader)],
      wasmHeader: File(ortWasmHeader),
      version: File(ortVersionFile),
    );

/// Generates wrappers for every API struct declared in [header].
Generated generate({
  required File header,
  required File bindings,
  List<File> extraHeaders = const [],
  File? wasmHeader,
  File? version,
}) {
  final headerText = header.readAsStringSync();
  final apis = parseApis(headerText);
  // Callback typedefs cross the seam as addresses: ffigen types them
  // as `dart:ffi` typedefs, which do not exist on the web.
  final callbacks = parseFunctionPointers(headerText);
  for (final extra in extraHeaders) {
    apis.addAll(parseApis(extra.readAsStringSync()));
  }
  final signatures = readApiSignatures(bindings);

  // Keyed by (struct, group), because a wrapper is an extension on the struct
  // that declares it and two structs can declare the same name.
  final byFile = <(String, String), List<String>>{};
  final skipped = <String>[];
  final raw = <RawOperation>[];

  for (final api in apis.entries) {
    final members = signatures[api.key];
    if (members == null) continue;

    for (final function in api.value) {
      final group = groupOf(function.name);
      final name = '${api.key}.${function.name}';
      final signature = members[function.name];
      if (signature == null) {
        skipped.add('$name: not in the ffigen bindings');
        continue;
      }

      final wrapper = emit(function, signature);
      if (wrapper == null) {
        skipped.add('$name: ${unmappedReasons(function).join(', ')}');
        continue;
      }
      (byFile[(api.key, group)] ??= []).add(wrapper.code);
      raw.add((
        name: dartName(function.name),
        c: function.name,
        owner: api.key,
        wrapper: wrapper,
      ));
    }
  }

  // The hand-written seam takes precedence: an operation it already declares
  // is the translated one, and generating a native-only twin of it would put
  // two meanings on one name. Read from the file rather than listed, so adding
  // a hand-written operation is enough and nothing here has to be told.
  final translated = _declaredBy(File('lib/src/backend/interface.dart'));
  final rawOnly = [
    for (final operation in raw)
      if (!translated.contains(operation.name) &&
          !touchesInternalType(operation.wrapper))
        operation,
  ]..sort((a, b) => a.name.compareTo(b.name));

  final names = [
    for (final key in byFile.keys) '${fileName(key.$1, key.$2)}.g.dart',
  ]..sort();

  return Generated(
    files: {
      for (final entry in byFile.entries)
        '${fileName(entry.key.$1, entry.key.$2)}.g.dart':
            _formatter.format(_source(entry.key.$1, entry.key.$2, entry.value)),
      'api.g.dart': _formatter.format(_barrel(names)),
      'unmapped.txt': _unmapped(skipped),
      '../../backend/platform_support.g.dart':
          _formatter.format(_supportSource()),
      if (version != null)
        '../../version.g.dart': _formatter
            .format(_versionSource(version.readAsStringSync().trim())),
      if (wasmHeader != null)
        '../../backend/wasm/api.g.dart': _formatter
            .format(_wasmSource(parseWasmApi(wasmHeader.readAsStringSync()))),
      '../../backend/handles.g.dart': _formatter
          .format(handlesFile(handlesIn(rawOnly.map((o) => o.wrapper)))),
      '../../backend/raw_interface.g.dart':
          _formatter.format(rawInterfaceFile(rawOnly, callbacks)),
      '../../backend/raw_ffi_calls.g.dart':
          _formatter.format(rawFfiFile(rawOnly, callbacks)),
      '../../backend/raw_wasm_calls.g.dart':
          _formatter.format(rawWasmFile(rawOnly, callbacks)),
    },
    skipped: skipped,
    wrappers: byFile.values.fold(0, (n, methods) => n + methods.length),
  );
}

/// `OrtApi` calls keep the plain group name; the sibling tables are prefixed.
String fileName(String struct, String group) =>
    struct == 'OrtApi' ? group : '${_snake(struct)}_$group';

String _snake(String name) => name
    .replaceAllMapped(RegExp(r'(?<=[a-z0-9])([A-Z])'), (m) => '_${m[1]}')
    .toLowerCase();

String _capital(String name) => name[0].toUpperCase() + name.substring(1);

/// Re-exports every wrapper file, so adding a group does not mean remembering
/// to export it.
String _barrel(List<String> files) => '''
// AUTO GENERATED FILE, DO NOT EDIT.
//
// Generated by tool/generate_bindings.dart from the pinned headers.

/// Dart wrappers over the ONNX Runtime C API.
///
/// The hand-written wrappers are exported alongside the generated ones, so a
/// caller reaches every wrapped call the same way and does not have to know
/// which kind it is. `unmapped.txt` says which calls are which.
library;

export 'manual.dart';

${files.map((f) => "export '$f';").join('\n')}
''';

/// Why a call has no wrapper, where the answer is not "nobody has written one".
///
/// Distinguishes work left to do from work that cannot be done, so the list
/// does not read as a backlog when it is not one.
const _cannotBeWrapped = <String, String>{
  'GetOpaqueValue': 'the caller supplies a struct whose layout only the custom '
      'op that registered the opaque type knows. Nothing on this side can '
      'declare it, so there is no signature to generate',
};

String _unmapped(List<String> skipped) {
  final byHand = _handWritten();
  String annotate(String entry) {
    final name = RegExp(r'^(?:\w+\.)?(\w+):').firstMatch(entry)?.group(1);
    if (byHand.contains(name)) return '$entry [wrapped by hand]';
    if (_cannotBeWrapped[name] case final reason?) {
      return '$entry\n    cannot be wrapped: $reason';
    }
    return entry;
  }

  return 'Functions the generator does not handle.\n'
      'Each needs a rule in tool/src/types.dart, or a wrapper written by hand\n'
      'in lib/src/bindings/api/manual.dart.\n'
      '\n'
      'Marked [wrapped by hand] means it is not generated but is still\n'
      'callable: manual.dart wraps it, for a reason its doc comment gives.\n'
      'Unmarked means there is no wrapper at all.\n\n'
      '${([...skipped].map(annotate).toList()..sort()).join('\n')}\n';
}

/// The C names manual.dart wraps, read back from the file itself.
///
/// Each hand-written wrapper names its C call on the first line of its doc
/// comment, the same as a generated one. Reading them back is what keeps this
/// record true: hand-writing a wrapper updates the file that says which calls
/// have none, without anyone having to remember to.
Set<String> _handWritten() {
  final file = File('lib/src/bindings/api/manual.dart');
  if (!file.existsSync()) return const {};
  // Every backticked name on a doc line, not just the first: a wrapper that
  // covers a pair names both, as `availableProviders` names the release it
  // makes on the caller's behalf. Names that are not C calls match nothing and
  // do no harm.
  return {
    for (final line in file.readAsLinesSync())
      if (line.trimLeft().startsWith('///'))
        for (final match in RegExp(r'`(\w+)`').allMatches(line))
          match.group(1)!,
  };
}

/// Which platforms provide each operation, from the correspondence table.
///
/// Emitted so the table is load-bearing rather than merely checked: a test
/// asserts the WebAssembly backend refuses exactly the operations marked
/// unavailable here, and no others.
String _supportSource() {
  // Every operation the interface declares, not only those the correspondence
  // table names. The table holds the ones whose names differ, so generating
  // from it alone left two thirds of the seam unchecked, and a refusal nobody
  // checks is how four of them came to claim limits that were not there.
  //
  // An operation the table does not mention has no WebAssembly counterpart and
  // is native only. If that is wrong the backend disagrees and
  // platform_support_test fails, which is the point.
  final described = {
    for (final operation in correspondence) operation.name: operation,
  };
  final declared = _declaredBy(File('lib/src/backend/interface.dart'));

  final entries = [
    for (final name in ({...declared, ...described.keys}.toList()..sort()))
      if (described[name] case final operation?)
        "  '$name': (native: ${operation.native != null}, "
            "web: ${operation.onWeb}),"
      else
        throw StateError(
          'the seam declares $name and tool/src/seam.dart does not describe '
          'it. Add an entry saying what it corresponds to on each platform, '
          'or the support table silently calls it native only and nothing '
          'checks the refusal.',
        ),
  ].join('\n');

  final asyncify =
      asyncifyRefuses.map((name) => "  '$name',").join('\n');

  return """
// AUTO GENERATED FILE, DO NOT EDIT.
//
// Generated by tool/generate_bindings.dart from the pinned headers.

/// Which platforms provide each operation the seam exposes.
///
/// Derived from which header declares it. An operation in both is portable; an
/// operation in one is that platform's alone, and the backend that lacks it
/// says so rather than pretending.
const platformSupport = <String, ({bool native, bool web})>{
$entries
};

/// What the Asyncify backend refuses on top of the plain one.
///
/// There are two WebAssembly backends. The plain build cannot suspend, so
/// every call returns a result. The Asyncify build can, and hands back a
/// promise a synchronous signature has nowhere to put, so the calls that
/// suspend are refused there and only there.
///
/// [platformSupport] has one flag for "web" and cannot express this, which is
/// why it is listed separately rather than folded in: the WebGPU and WebNN
/// builds are Asyncify, so this is what an accelerated page actually gets.
const asyncifyRefuses = <String>[
$asyncify
];
""";
}

/// The pinned ONNX Runtime version, as a constant.
///
/// Read from the submodule's VERSION_NUMBER so nothing can disagree with it.
/// The WebAssembly build exports no version string, so the web backend has to
/// answer from this rather than from the runtime.
String _versionSource(String version) => """
// AUTO GENERATED FILE, DO NOT EDIT.
//
// Generated by tool/generate_bindings.dart from the pinned headers.

/// The ONNX Runtime version these bindings were generated against.
const ortVersion = '$version';
""";

/// The WebAssembly build's exports, one external per function.
///
/// Everything here is a number or a bool, because a wasm heap is one flat
/// address space: pointers, handles and sizes are all indices into it. The
/// marshalling lives above this, in the same place it does for native.
String _wasmSource(List<WasmFunction> functions) {
  final members = functions.map(_wasmMember).join('\n\n');
  return """
// AUTO GENERATED FILE, DO NOT EDIT.
//
// Generated by tool/generate_bindings.dart from the pinned headers.

import 'dart:js_interop';

import 'module.dart';

/// The functions `onnxruntime/wasm/api.h` exports.
extension OrtWasmApi on OrtModule {
$members
}
""";
}

String _wasmMember(WasmFunction function) {
  final parameters =
      function.parameters.map((p) => '${p.$1} ${p.$2}').join(', ');
  return "  @JS('${function.exported}')\n"
      '  external ${function.returns} ${function.dartName}($parameters);';
}

String _source(String struct, String group, List<String> methods) => '''
// AUTO GENERATED FILE, DO NOT EDIT.
//
// Generated by tool/generate_bindings.dart from the pinned headers.

import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../ort_bindings.g.dart';
import 'support.dart';

/// ${_capital(group)} calls on `$struct`.
extension $struct${_capital(group)}Api on $struct {
${methods.join('\n')}}
''';

/// The operation names a backend interface already declares.
///
/// Parsed rather than listed. The hand-written seam is the authority on what
/// it covers, and a list here would be a second place to keep in step.
Set<String> _declaredBy(File interface) {
  if (!interface.existsSync()) return const {};
  return {
    for (final match in RegExp(
      r'^\s{2}(?:@\w+[^\n]*\n\s*)*[A-Za-z][\w<>,?\[\] ]*\s+(\w+)\(',
      multiLine: true,
    ).allMatches(interface.readAsStringSync()))
      match.group(1)!,
  };
}

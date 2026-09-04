/// The raw half of the seam: every C API call, on both platforms.
///
/// The hand-written backends carry the operations that genuinely run in both
/// places, and those are a translation between two differently factored C APIs
/// that [seam.dart]'s table describes. This is the rest: the several hundred
/// calls the native API has and the WebAssembly build does not.
///
/// They are here so that an application can compile for the web while using
/// them on native. Reaching them through `dart:ffi` instead means importing
/// `native.dart`, and one such import fails a web build outright, which makes
/// the whole native API unusable to anyone who also ships a web target.
///
/// Nothing here needs a table entry. A call the WebAssembly build exports is
/// the table's business; a call only native has is this file's, and being
/// absent from the wasm exports is what identifies it.
library;

import 'emit.dart';

/// A handle as the seam spells it.
///
/// `Pointer<OrtSession>` becomes `OrtSessionPtr`, an extension type over the
/// address. Any other pointer becomes a plain `OrtPtr`: the seam's currency is
/// an address, and only the opaque handles are worth distinguishing.
String seamType(String dart, Set<String> callbacks) {
  // A callback crosses as its address. ffigen types one as a `dart:ffi`
  // typedef, which does not exist on the web, and the runtime stores it and
  // calls it later, so only the caller can own the lifetime either way.
  if (callbacks.contains(dart)) return 'OrtPtr';
  return dart.replaceAllMapped(RegExp(r'Pointer<(\w+)>'), (match) {
    final name = match.group(1)!;
    return name.startsWith('Ort') ? '${name}Ptr' : 'OrtPtr';
  });
}

/// Every opaque handle named across [wrappers].
/// Types that look like a handle and are not.
///
/// `OrtStatus` is how the C API reports failure. It never crosses the seam:
/// `checkOrtStatus` reads it and releases it inside the wrapper. Generating a
/// handle for it would also collide with the `OrtStatusPtr` typedef ffigen
/// already emits.
const _notHandles = {'OrtStatus'};

Set<String> handlesIn(Iterable<Wrapper> wrappers) => {
      for (final wrapper in wrappers)
        for (final type in [
          wrapper.returns,
          ...wrapper.parameters.map((p) => p.$1),
        ])
          for (final match in RegExp(r'Pointer<(Ort\w+)>').allMatches(type))
            if (!_notHandles.contains(match.group(1)!)) match.group(1)!,
    };

/// Turns a seam value into what the native wrapper takes.
String toNative(String dartType, String name, Set<String> callbacks) {
  if (callbacks.contains(dartType)) {
    // The target type is inferred from the parameter it is passed to.
    return 'Pointer<Never>.fromAddress($name.address).cast()';
  }
  final list = RegExp(r'^List<Pointer<(\w+)>>$').firstMatch(dartType);
  if (list != null) {
    return '[for (final h in $name) '
        'Pointer<${list.group(1)}>.fromAddress(h.address)]';
  }
  final one = RegExp(r'^Pointer<(\w+)>$').firstMatch(dartType);
  if (one != null) {
    return 'Pointer<${one.group(1)}>.fromAddress($name.address)';
  }
  return name;
}

/// Turns what the native wrapper returned into what the seam declares.
String toSeam(String dartType, String value) {
  String handleFor(String name) =>
      name.startsWith('Ort') ? '${name}Ptr' : 'OrtPtr';

  final list = RegExp(r'^List<Pointer<(\w+)>>$').firstMatch(dartType);
  if (list != null) {
    return '[for (final p in $value) ${handleFor(list.group(1)!)}(p.address)]';
  }
  final one = RegExp(r'^Pointer<(\w+)>$').firstMatch(dartType);
  if (one != null) {
    return '${handleFor(one.group(1)!)}($value.address)';
  }
  return value;
}

/// The field types of a record type, or null when [type] is not one.
///
/// A wrapper with several out-parameters returns a record, and any field of it
/// may be a handle that needs converting on the way out.
List<String>? recordFields(String type) {
  if (!type.startsWith('(') || !type.endsWith(')')) return null;
  final inner = type.substring(1, type.length - 1);
  final fields = <String>[];
  var depth = 0;
  var start = 0;
  for (var i = 0; i < inner.length; i++) {
    final character = inner[i];
    if (character == '<' || character == '(') depth++;
    if (character == '>' || character == ')') depth--;
    if (character == ',' && depth == 0) {
      fields.add(inner.substring(start, i).trim());
      start = i + 1;
    }
  }
  fields.add(inner.substring(start).trim());
  // Each field is written "Type name"; the type is everything but the name.
  return [
    for (final field in fields)
      field.contains(' ')
          ? field.substring(0, field.lastIndexOf(' ')).trim()
          : field,
  ];
}

/// Whether anything in [type] has to be converted crossing the seam.
bool crosses(String type) => type.contains('Pointer<');

/// One raw operation: the seam name, and the wrapper it forwards to.
typedef RawOperation = ({
  String name,
  String c,
  String owner,
  Wrapper wrapper,
});

/// How to reach the struct a call lives on.
///
/// The C API is not one table. `OrtApi` is reached through the loader, and it
/// carries accessors for four more: training, compilation, model editing and
/// interop. A call on one of those has to go through its own accessor, which is
/// why the owning struct travels with the operation.
const _accessor = <String, String>{
  'OrtApi': 'ortApiForStatus',
  'OrtTrainingApi': 'trainingApi().ref',
  'OrtCompileApi': '_compileApi',
  'OrtModelEditorApi': '_modelEditorApi',
  'OrtInteropApi': '_interopApi',
};

/// The getters the generated backend needs for the tables with no accessor of
/// their own in `runtime.dart`.
///
/// Training already has one, with the availability check that belongs to it:
/// only the `full` build compiles it in. These three are present whenever the
/// library is, but the C API still returns null on a build without them, so a
/// null is reported rather than dereferenced.
const _accessorSource = r'''
  OrtCompileApi get _compileApi => _table(
        ortApiForStatus.GetCompileApi
            .asFunction<Pointer<OrtCompileApi> Function()>()(),
        'OrtCompileApi',
      ).ref;

  OrtModelEditorApi get _modelEditorApi => _table(
        ortApiForStatus.GetModelEditorApi
            .asFunction<Pointer<OrtModelEditorApi> Function()>()(),
        'OrtModelEditorApi',
      ).ref;

  OrtInteropApi get _interopApi => _table(
        ortApiForStatus.GetInteropApi
            .asFunction<Pointer<OrtInteropApi> Function()>()(),
        'OrtInteropApi',
      ).ref;

  /// Refuses a null table rather than dereferencing it.
  Pointer<T> _table<T extends NativeType>(Pointer<T> table, String name) =>
      table == nullptr
          ? throw StateError(
              'this build of ONNX Runtime has no $name. It is compiled in '
              'rather than always present, so a smaller build can lack it.',
            )
          : table;
''';

/// What to tell someone who reached one of these on the web.
const _whyText = "const _why = 'the WebAssembly build exports forty functions "
    "of its own rather '\n    'than the OrtApi struct, and this is not one of "
    "them';";

const _banner = '''
// AUTO GENERATED FILE, DO NOT EDIT.
//
// Generated by tool/generate_bindings.dart from the pinned headers.
''';

/// The handle types, as extension types over an address.
///
/// Each implements [OrtPtr], so a typed handle can be passed anywhere the
/// hand-written seam takes an untyped one, while a tensor still cannot be
/// passed where a session is expected. Being an integer underneath is what
/// lets them exist on a platform without `dart:ffi`.
String handlesFile(Set<String> handles) {
  final sorted = handles.toList()..sort();
  return '''
$_banner
/// The opaque handles the C API deals in, one type each.
///
/// An address, the same as [OrtPtr], but distinguishable: passing a tensor
/// where a session belongs is a mistake the C API cannot catch and this can.
/// Each implements [OrtPtr] so it still flows into the hand-written seam.
library;

import 'types.dart';

${sorted.map((h) => '/// A `$h`.\n'
          'extension type const ${h}Ptr(int address) implements OrtPtr {}').join('\n\n')}
''';
}

/// The declarations, added to the seam the hand-written interface starts.
String rawInterfaceFile(List<RawOperation> operations, Set<String> callbacks) => '''
$_banner
/// Every C API call the WebAssembly build does not have.
///
/// Separated from the hand-written interface only by how it is produced. A
/// caller sees one API: `OrtCalls` implements this, so both halves arrive
/// together and neither has to be found.
///
/// Every one of these is native only, which is why each carries [NativeOnly].
/// The web backend answers them by refusing, which is what lets an application
/// using them compile for the web at all.
library;

import '../annotations.dart';
import 'handles.g.dart';
import 'types.dart';

$_whyText

/// The calls only the native runtime can make.
abstract interface class OrtRawCalls {
${operations.map((o) => _declaration(o, callbacks)).join('\n')}}
''';

String _declaration(RawOperation operation, Set<String> callbacks) {
  final parameters = operation.wrapper.parameters
      .map((p) => '${seamType(p.$1, callbacks)} ${p.$2}')
      .join(', ');
  return '  /// `${operation.c}`\n'
      '  @NativeOnly(_why)\n'
      '  ${seamType(operation.wrapper.returns, callbacks)} ${operation.name}'
      '($parameters);\n';
}

/// The native half: forward, converting handles at the boundary.
String rawFfiFile(List<RawOperation> operations, Set<String> callbacks) => '''
$_banner
/// The generated half of the native backend.
///
/// Each call converts its handles back into pointers and forwards to the
/// generated wrapper over `OrtApi`. Nothing here decides anything, which is
/// why it can be generated: the decisions live in ffi_calls.dart, and an
/// override there replaces the version below.
library;

import 'dart:ffi';

import '../bindings/api/api.g.dart';
import '../bindings/api/support.dart';
import '../bindings/ort_bindings.g.dart';
import '../ffi/runtime.dart';
import 'handles.g.dart';
import 'raw_interface.g.dart';
import 'types.dart';

/// Every native-only call, forwarded.
base mixin GeneratedFfiRawCalls implements OrtRawCalls {
$_accessorSource
${operations.map((o) => _ffiMethod(o, callbacks)).join('\n')}}
''';

String _ffiMethod(RawOperation operation, Set<String> callbacks) {
  final wrapper = operation.wrapper;
  final parameters =
      wrapper.parameters.map((p) => '${seamType(p.$1, callbacks)} ${p.$2}').join(', ');
  final arguments =
      wrapper.parameters.map((p) => toNative(p.$1, p.$2, callbacks)).join(', ');
  final table = _accessor[operation.owner] ?? 'ortApiForStatus';
  final call = '$table.${operation.name}($arguments)';
  final returns = seamType(wrapper.returns, callbacks);
  final head = '  @override\n  $returns ${operation.name}($parameters)';

  if (wrapper.returns == 'void') return '$head => $call;\n';

  final fields = recordFields(wrapper.returns);
  if (fields != null && fields.any(crosses)) {
    final read = [
      for (final (index, field) in fields.indexed)
        toSeam(field, 'result.\$${index + 1}'),
    ].join(', ');
    return '$head {\n'
        '    final result = $call;\n'
        '    return ($read);\n'
        '  }\n';
  }
  if (!crosses(wrapper.returns)) return '$head => $call;\n';
  return '$head => ${toSeam(wrapper.returns, call)};\n';
}

/// The web half: refuse, by name, with the reason.
String rawWasmFile(List<RawOperation> operations, Set<String> callbacks) => '''
$_banner
/// The generated half of the WebAssembly backend.
///
/// Every call here is one the web build does not export. Refusing by name is
/// the whole point: the application compiles, and the limit is reported where
/// it is reached rather than at the import.
///
/// It names nothing native, which is what lets it be the web half of the
/// conditional export in calls.dart.
library;

import '../annotations.dart';
import 'handles.g.dart';
import 'raw_interface.g.dart';
import 'types.dart';

$_whyText

/// Every native-only call, refused.
base mixin GeneratedWasmRawCalls implements OrtRawCalls {
${operations.map((o) => _wasmMethod(o, callbacks)).join('\n')}}
''';

String _wasmMethod(RawOperation operation, Set<String> callbacks) {
  final parameters = operation.wrapper.parameters
      .map((p) => '${seamType(p.$1, callbacks)} ${p.$2}')
      .join(', ');
  return '  @override\n'
      '  @NativeOnly(_why)\n'
      '  ${seamType(operation.wrapper.returns, callbacks)} ${operation.name}'
      '($parameters) =>\n'
      "      unsupportedOnWeb('${operation.c}', _why);\n";
}

/// Whether [wrapper] mentions a type the seam deliberately does not carry.
///
/// `ReleaseStatus` and its kin take an `OrtStatus`, which the wrappers already
/// read and release for the caller. Putting them on the seam would offer a way
/// to release a status twice, and the seam has no type for one on purpose.
bool touchesInternalType(Wrapper wrapper) => [
      wrapper.returns,
      ...wrapper.parameters.map((p) => p.$1),
    ].any((type) =>
        _notHandles.any((name) => type.contains('Pointer<$name>')));

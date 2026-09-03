/// Turns the parsed C API into Dart wrappers.
///
/// One file per handle type, because that is how the C API is organised once
/// you group by the type each function takes. What cannot be mapped is not
/// emitted and not guessed at: it is returned for the caller to write down.
library;

import 'c_api.dart';
import 'types.dart';

/// One call, in the three forms the seam needs it in.
///
/// The shape the base package hand-writes: an interface in Dart types and
/// handles, a backend that marshals and forwards, and a class above the
/// boundary that touches neither. Generated here rather than written, because
/// GenAI's surface is a hundred and thirty mechanical calls where the base
/// package's portable set is a curated one.
final class Wrapped {
  const Wrapped({
    required this.declaration,
    required this.implementation,
    required this.unsupported,
    required this.method,
  });

  /// The signature on the interface. No `dart:ffi`, which is what lets the
  /// package compile into a web application at all.
  final String declaration;

  /// What the FFI backend does to satisfy it.
  final String implementation;

  /// What a platform with no GenAI build does instead, which is refuse.
  final String unsupported;

  /// What the public class offers, forwarding to whichever backend was picked.
  final String method;
}

/// What a run produced.
final class Emitted {
  Emitted({required this.files, required this.skipped, required this.wrappers});

  final Map<String, String> files;
  final List<String> skipped;
  final int wrappers;
}

/// The key functions that belong to no handle are filed under.
const _globals = '(globals)';

/// Whether [parameter] is where a result is written rather than an input.
///
/// Two signals, and the structural one is the reliable half. Most out
/// parameters are named `out`, but not all of them: OgaLoadAudios calls its
/// `audios`. A pointer to a pointer is always somewhere to put a handle, and
/// that holds whatever it is called.
bool _isOut(CParameter parameter) =>
    parameter.type.endsWith('**') ||
    parameter.name == 'out' ||
    parameter.name.startsWith('out_');

/// The parameter [function] writes its result into, if it has one.
///
/// The last parameter, when it is somewhere to write: a pointer to a pointer,
/// a name that says so, or a non-const pointer to a scalar. Const marks an
/// input, so its absence on a pointer is the signal, and it holds where the
/// name does not: OgaTokenizerGetBosTokenId calls its out parameter `token_id`.
CParameter? _outOf(CFunction function) {
  if (!function.canFail || function.parameters.isEmpty) return null;
  final last = function.parameters.last;
  if (_isOut(last)) return last;
  final type = last.type;
  if (type.startsWith('const ') || !type.endsWith('*')) return null;
  return nativeSlot(type.substring(0, type.length - 1)) == null ? null : last;
}

/// A list parameter and how to get it into the arena.
final class _ListParameter {
  const _ListParameter({required this.dart, required this.element});

  final String dart;
  final String element;

  String setUp(String name) {
    final value =
        dart == 'List<String>' ? 'cString(arena, $name[i])' : '$name[i]';
    return 'final ${name}Native = arena<$element>($name.length);\n'
        '        for (var i = 0; i < $name.length; i++) {\n'
        '          ${name}Native[i] = $value;\n'
        '        }';
  }
}

/// The list [parameters] starting at [index] describe, if they describe one.
_ListParameter? _asList(List<CParameter> parameters, int index) {
  if (index + 1 >= parameters.length) return null;
  final pointer = parameters[index].type.replaceAll('const ', '').trim();
  final count = parameters[index + 1].type.replaceAll('const ', '').trim();
  if (count != 'size_t') return null;
  return switch (pointer) {
    'int32_t*' => const _ListParameter(dart: 'List<int>', element: 'Int32'),
    'int64_t*' => const _ListParameter(dart: 'List<int>', element: 'Int64'),
    'float*' => const _ListParameter(dart: 'List<double>', element: 'Float'),
    // An array of C strings. Each one is copied into the arena and freed with
    // it, so the callee sees them for exactly the length of the call.
    'char*const*' ||
    'char**' =>
      const _ListParameter(dart: 'List<String>', element: 'Pointer<Char>'),
    _ => null,
  };
}

String _dartParameterName(String name) => _lowerFirst(name
    .split('_')
    .map((p) => p.isEmpty ? p : p[0].toUpperCase() + p.substring(1))
    .join());

String _lowerFirst(String value) =>
    value.isEmpty ? value : value[0].toLowerCase() + value.substring(1);

/// The Dart method name for [function] on [owner].
String _methodName(CFunction function, String owner) {
  var name = function.name.substring(3); // Oga
  final type = owner.substring(3); // Model, Generator, ...
  if (name.startsWith(type)) name = name.substring(type.length);
  if (name.startsWith('_')) name = name.substring(1);
  return _lowerFirst(name.isEmpty ? type : name);
}

String _fileNameFor(String owner) {
  final buffer = StringBuffer();
  final name = dartNameOf(owner);
  for (var i = 0; i < name.length; i++) {
    final ch = name[i];
    if (i > 0 && ch.toUpperCase() == ch && ch.toLowerCase() != ch) {
      buffer.write('_');
    }
    buffer.write(ch.toLowerCase());
  }
  return '${buffer.toString()}.g.dart';
}

/// Wrappers for every handle type the header describes.

/// The name this call takes on the seam, which spans every handle and so has
/// to stay unique across them.
String _callName(CFunction function) {
  // Upstream writes both OgaModelGetType and OgaGenerator_IsDone. The
  // underscore is theirs, not Dart's, so it is folded into the camel case
  // rather than carried into a name the analyser complains about.
  final parts = function.name.substring(3).split('_');
  final joined = parts.first +
      parts
          .skip(1)
          .map((p) => p.isEmpty ? p : p[0].toUpperCase() + p.substring(1))
          .join();
  return _lowerFirst(joined);
}

/// Why a function was left out, for unmapped.txt.
String _why(CFunction function) {
  if (function.takesCallback) return 'takes a callback, which needs a wrapper';
  if (function.parameters.isEmpty) return 'takes nothing this can act on';
  for (final parameter in function.parameters) {
    if (map(parameter.type) == null && !parameter.isHandleOut) {
      return 'parameter ${parameter.name} is ${parameter.type}';
    }
  }
  return 'returns ${function.returns}';
}

/// The seam, the backend and the classes above it.
Emitted emit(List<CFunction> functions) {
  final skipped = <String>[];
  final byOwner = <String, List<CFunction>>{};
  for (final function in functions) {
    byOwner.putIfAbsent(function.owner ?? _globals, () => []).add(function);
  }

  final declarations = StringBuffer();
  final implementations = StringBuffer();
  final refusals = StringBuffer();
  final files = <String, String>{};
  var wrappers = 0;

  // Globals first, so the interface reads in the order the header does.
  final globalMethods = StringBuffer();
  for (final function in byOwner.remove(_globals) ?? <CFunction>[]) {
    final wrapped = _wrap(function, null, null);
    if (wrapped == null) {
      skipped.add('${function.name}: ${_why(function)}');
      continue;
    }
    declarations.writeln(wrapped.declaration);
    implementations.writeln(wrapped.implementation);
    refusals.writeln(wrapped.unsupported);
    globalMethods.writeln(wrapped.method);
    wrappers++;
  }

  for (final entry in byOwner.entries) {
    final owner = entry.key;
    final dartName = dartNameOf(owner);
    final body = StringBuffer();

    final destructor = entry.value.where((f) => f.isDestructor).firstOrNull;
    if (destructor == null) {
      for (final f in entry.value) {
        skipped.add('${f.name}: $owner has no destructor, so it is not owned');
      }
      continue;
    }

    // Every handle frees itself the same way, so that one is written here
    // rather than mapped like the rest.
    final destroy = _callName(destructor);
    declarations.writeln('  /// Wraps `${destructor.name}`.\n'
        '  void $destroy(GenAiPtr handle);\n');
    implementations.writeln('  @override\n'
        '  void $destroy(GenAiPtr handle) =>\n'
        '      ${destructor.name}(pointer<$owner>(handle));\n');
    refusals.writeln('  @override\n'
        '  void $destroy(GenAiPtr handle) =>\n'
        "      throw const GenAiUnsupported('$destroy');\n");
    body.writeln('  @override\n'
        '  void destroy(GenAiPtr handle) => _calls.$destroy(handle);\n');
    wrappers++;

    for (final function in entry.value) {
      if (function.isDestructor) continue;
      final wrapped = _wrap(function, owner, dartName);
      if (wrapped == null) {
        skipped.add('${function.name}: ${_why(function)}');
        continue;
      }
      declarations.writeln(wrapped.declaration);
      implementations.writeln(wrapped.implementation);
      refusals.writeln(wrapped.unsupported);
      body.writeln(wrapped.method);
      wrappers++;
    }

    files[_fileNameFor(owner)] =
        _classFile(owner: owner, dartName: dartName, body: body.toString());
  }

  if (globalMethods.isNotEmpty) {
    files['genai.g.dart'] = _globalsFile(globalMethods.toString());
  }

  final parts = files.keys.toList()..sort();
  files['api.dart'] = _libraryFile(parts);
  files['../backend/interface.dart'] = _interfaceFile(declarations.toString());
  files['../backend/ffi_calls.dart'] = _ffiFile(implementations.toString());
  files['../backend/unsupported_calls.dart'] =
      _unsupportedFile(refusals.toString());
  return Emitted(files: files, skipped: skipped, wrappers: wrappers);
}

/// One call in its three forms, or null when something about it is not
/// understood.
///
/// [owner] is null for a function that belongs to no handle, which becomes a
/// top level function rather than a method.
Wrapped? _wrap(CFunction function, String? owner, String? dartName) {
  if (function.takesCallback) return null;
  final parameters = function.parameters;
  final out = _outOf(function);

  final selfIndex = owner == null
      ? -1
      : parameters.indexWhere((p) => p.pointee == owner && !p.isHandleOut);
  final isFactory = owner != null &&
      function.name.startsWith('OgaCreate') &&
      out != null &&
      out.pointee == owner;
  if (owner != null && !isFactory && selfIndex < 0) return null;

  // The three parameter lists: what the interface declares, what the backend
  // passes on, and what the class above takes.
  final declared = <String>[];
  final forwarded = <String>[];
  final passed = <String>[];
  final prologue = <String>[];

  // The Dart signature leads with the handle, which is the convention on this
  // side. The forwarded call follows the C order instead, because the receiver
  // is not always first there: OgaAppendTokenSequence takes it last.
  if (owner != null && !isFactory) {
    declared.add('GenAiPtr handle');
    passed.add('handle');
  }

  for (var i = 0; i < parameters.length; i++) {
    final parameter = parameters[i];
    if (parameter == out) continue;
    if (owner != null && !isFactory && i == selfIndex) {
      forwarded.add('pointer<$owner>(handle)');
      continue;
    }

    final list = _asList(parameters, i);
    if (list != null) {
      final name = _dartParameterName(parameter.name);
      declared.add('${list.dart} $name');
      passed.add(name);
      prologue.add(list.setUp(name));
      forwarded.add('${name}Native');
      forwarded.add('$name.length');
      i++;
      continue;
    }

    final mapped = map(parameter.type);
    if (mapped == null) return null;
    final name = _dartParameterName(parameter.name);
    if (mapped.isString) {
      declared.add('String $name');
      forwarded.add('cString(arena, $name)');
    } else if (mapped.isHandle) {
      declared.add('GenAiPtr $name');
      forwarded.add('pointer<${parameter.pointee}>($name)');
    } else {
      declared.add('${mapped.dart} $name');
      forwarded.add(name);
    }
    passed.add(name);
  }

  final name = _callName(function);
  final setUp =
      prologue.isEmpty ? '' : '${prologue.map((l) => '      $l').join('\n')}\n';
  final signature = declared.join(', ');
  final arguments = passed.join(', ');

  String? returns;
  String body;

  final producesHandle =
      out != null && out.isHandleOut && out.pointee.startsWith('Oga');
  if (isFactory || producesHandle) {
    final produced = isFactory ? owner : out.pointee;
    returns = 'GenAiPtr';
    body = '''
$setUp      final out = arena<Pointer<$produced>>();
      check(${function.name}(${[...forwarded, 'out'].join(', ')}));
      return handleOf(out.value);''';
  } else if (!function.canFail) {
    final mapped = map(function.returns);
    if (mapped == null || prologue.isNotEmpty) return null;
    returns = mapped.dart;
    final call = '${function.name}(${forwarded.join(', ')})';
    body = mapped.dart == 'void' ? '      $call;' : '      return $call;';
  } else if (out == null) {
    returns = 'void';
    body = '$setUp      check(${function.name}(${forwarded.join(', ')}));';
  } else {
    final scalar = map(out.type.replaceFirst('*', ''));
    if (scalar == null) return null;
    if (scalar.isString) {
      returns = 'String';
      final take = function.transfersString ? 'takeCString' : 'borrowedCString';
      body = '''
$setUp      final out = arena<Pointer<Char>>();
      check(${function.name}(${[...forwarded, 'out'].join(', ')}));
      return $take(out.value);''';
    } else {
      final slot = nativeSlot(out.type.replaceFirst('*', ''));
      if (slot == null) return null;
      returns = scalar.dart;
      body = '''
$setUp      final out = arena<$slot>();
      check(${function.name}(${[...forwarded, 'out'].join(', ')}));
      return out.value;''';
    }
  }

  final declaration = '  /// Wraps `${function.name}`.\n'
      '  $returns $name($signature);\n';
  final implementation = '  @override\n'
      '  $returns $name($signature) => withArena((arena) {\n'
      '$body\n'
      '      });\n';

  // What the class above offers. It names no pointer type and does no
  // marshalling: that is the backend's job, on the other side of the seam.
  final String method;
  if (owner == null) {
    method = '/// Wraps `${function.name}`.\n'
        '$returns ${_lowerFirst(name)}($signature) =>\n'
        '    _calls.$name($arguments);\n';
  } else if (isFactory) {
    final type = dartName!;
    final named = function.name.substring('OgaCreate'.length);
    final constructor = named == type
        ? 'factory $type'
        : 'factory $type.${_lowerFirst(named.substring(type.length))}';
    method = '  /// Wraps `${function.name}`.\n'
        '  $constructor($signature) =>\n'
        '      $type._(_calls.$name($arguments));\n';
  } else {
    final produced = producesHandle ? out.pointee : null;
    final call = '_calls.$name($arguments)';
    final methodName = _methodName(function, owner);
    method = produced != null
        ? '  /// Wraps `${function.name}`.\n'
            '  ${dartNameOf(produced)} $methodName(${_above(declared)}) =>\n'
            '      ${dartNameOf(produced)}._($call);\n'
        : '  /// Wraps `${function.name}`.\n'
            '  $returns $methodName(${_above(declared)}) => $call;\n';
  }

  return Wrapped(
    declaration: declaration,
    implementation: implementation,
    unsupported: '  @override\n'
        '  $returns $name($signature) =>\n'
        "      throw const GenAiUnsupported('$name');\n",
    method: method,
  );
}

/// The signature a class method takes, which is the declared one without the
/// receiver: the class already knows its own handle.
String _above(List<String> declared) =>
    declared.where((d) => d != 'GenAiPtr handle').join(', ');

String _globalsFile(String body) => '''
// AUTO GENERATED FILE, DO NOT EDIT.
//
// Generated from third_party/onnxruntime-genai/src/ort_genai_c.h.
// Regenerate with `dart run tool/generate_bindings.dart` from this package.
//
// The functions that belong to no handle: logging, telemetry, the process wide
// device selection, and provider registration.

part of 'api.dart';

$body''';

String _interfaceFile(String body) => '''
// AUTO GENERATED FILE, DO NOT EDIT.
//
// Generated from third_party/onnxruntime-genai/src/ort_genai_c.h.
// Regenerate with `dart run tool/generate_bindings.dart` from this package.

/// The boundary between the shared code and a backend.
///
/// One interface, taking Dart types and [GenAiPtr]. Nothing here mentions
/// `dart:ffi`, so everything above this line compiles for the web as well as
/// for native. Only handles cross as [GenAiPtr]; everything else crosses as a
/// Dart value.
library;

import 'types.dart';

/// The calls a backend has to be able to make.
///
/// Failures throw [GenAiException]. The C API reports them by returning a
/// result object that has to be read and released, and the backend does that;
/// nothing above this line sees one.
abstract interface class GenAiCalls {
$body}
''';

String _ffiFile(String body) => '''
// AUTO GENERATED FILE, DO NOT EDIT.
//
// Generated from third_party/onnxruntime-genai/src/ort_genai_c.h.
// Regenerate with `dart run tool/generate_bindings.dart` from this package.

/// The native backend.
///
/// The only generated file that is native. It marshals Dart values into the
/// arena, forwards to the generated bindings, and turns a failed `OgaResult`
/// into a [GenAiException].
library;

import 'dart:ffi';

import '../bindings/genai_bindings.g.dart';
import 'ffi_support.dart';
import 'interface.dart';
import 'types.dart';

/// The backend for this platform.
GenAiCalls createCalls() => FfiGenAiCalls();

/// GenAI reached through `dart:ffi`.
final class FfiGenAiCalls implements GenAiCalls {
$body}
''';

String _unsupportedFile(String body) => '''
// AUTO GENERATED FILE, DO NOT EDIT.
//
// Generated from third_party/onnxruntime-genai/src/ort_genai_c.h.
// Regenerate with `dart run tool/generate_bindings.dart` from this package.

/// The backend for a platform GenAI has no build for.
///
/// Upstream publishes no WebAssembly library, so every call refuses rather
/// than pretending. The point is that the package still compiles into a web
/// application: an application that uses GenAI on native and something else on
/// the web should not fail to build because of an import.
///
/// It names nothing native, which is what lets it be the web half of the
/// conditional export in calls.dart.
library;

import 'interface.dart';
import 'types.dart';

/// The backend for this platform.
GenAiCalls createCalls() => const UnsupportedGenAiCalls();

/// GenAI where there is no GenAI.
final class UnsupportedGenAiCalls implements GenAiCalls {
  const UnsupportedGenAiCalls();

$body}
''';

String _classFile({
  required String owner,
  required String dartName,
  required String body,
}) =>
    '''
// AUTO GENERATED FILE, DO NOT EDIT.
//
// Generated from third_party/onnxruntime-genai/src/ort_genai_c.h.
// Regenerate with `dart run tool/generate_bindings.dart` from this package.

part of 'api.dart';

/// Wraps the `$owner` handle.
///
/// Above the backend boundary, so it names no pointer type and forwards
/// everything to whichever backend was selected for this platform.
final class $dartName extends GenAiHandle {
  $dartName._(super.handle);

$body}
''';

String _libraryFile(Iterable<String> parts) => '''
// AUTO GENERATED FILE, DO NOT EDIT.
//
// Generated from third_party/onnxruntime-genai/src/ort_genai_c.h.
// Regenerate with `dart run tool/generate_bindings.dart` from this package.

/// The generated classes over the GenAI API.
///
/// One library rather than one per type, because they construct each other and
/// a private constructor is private to its library.
library;

import '../backend/calls.dart';
import '../backend/interface.dart';
import '../backend/types.dart';

export '../backend/types.dart'
    show GenAiException, GenAiHandle, GenAiPtr, GenAiUnsupported;

${parts.map((p) => "part '$p';").join('\n')}

/// The backend for this platform, made once.
final GenAiCalls _calls = createCalls();
''';

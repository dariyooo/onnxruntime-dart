/// Turns the parsed C API into Dart wrappers.
///
/// One file per handle type, because that is how the C API is organised once
/// you group by the type each function takes. What cannot be mapped is not
/// emitted and not guessed at: it is returned for the caller to write down.
library;

import 'c_api.dart';
import 'types.dart';

/// What a run produced.
final class Emitted {
  Emitted({required this.files, required this.skipped, required this.wrappers});

  final Map<String, String> files;
  final List<String> skipped;
  final int wrappers;
}

/// The key functions that belong to no handle are filed under.
const _globals = '(globals)';

/// The out-parameter convention upstream follows without exception.
bool _isOut(CParameter parameter) =>
    parameter.name == 'out' || parameter.name.startsWith('out_');

/// A list parameter and how to get it into the arena.
final class _ListParameter {
  const _ListParameter({required this.dart, required this.element});

  final String dart;
  final String element;

  String setUp(String name) =>
      'final ${name}Native = arena<$element>($name.length);\n'
      '        for (var i = 0; i < $name.length; i++) {\n'
      '          ${name}Native[i] = $name[i];\n'
      '        }';
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
Emitted emit(List<CFunction> functions) {
  final skipped = <String>[];
  final byOwner = <String, List<CFunction>>{};
  for (final function in functions) {
    final owner = function.owner;
    // A function that takes no handle is a global: logging, telemetry, the
    // process wide GPU device, provider registration. They are as much part of
    // the API as the methods are, so they get a library rather than a class.
    byOwner.putIfAbsent(owner ?? _globals, () => []).add(function);
  }

  final files = <String, String>{};
  var wrappers = 0;

  final globals = byOwner.remove(_globals) ?? [];
  final freeBody = StringBuffer();
  var freeCount = 0;
  for (final function in globals) {
    final wrapper = _free(function);
    if (wrapper == null) {
      skipped.add('${function.name}: ${_why(function)}');
      continue;
    }
    freeBody.writeln(wrapper);
    freeCount++;
  }
  if (freeCount > 0) {
    files['genai.g.dart'] = _globalsFile(freeBody.toString());
    wrappers += freeCount;
  }

  for (final entry in byOwner.entries) {
    final owner = entry.key;
    final dartName = dartNameOf(owner);
    final body = StringBuffer();
    var emittedHere = 0;

    final destructor = entry.value.where((f) => f.isDestructor).firstOrNull;
    if (destructor == null) {
      for (final f in entry.value) {
        skipped.add('${f.name}: $owner has no destructor, so it is not owned');
      }
      continue;
    }

    for (final function in entry.value) {
      if (function.isDestructor) continue;
      final wrapper = _wrap(function, owner, dartName);
      if (wrapper == null) {
        skipped.add('${function.name}: ${_why(function)}');
        continue;
      }
      body.writeln(wrapper);
      emittedHere++;
    }

    files[_fileNameFor(owner)] = _file(
      owner: owner,
      dartName: dartName,
      destructor: destructor.name,
      body: body.toString(),
    );
    wrappers += emittedHere;
  }

  return Emitted(files: files, skipped: skipped, wrappers: wrappers);
}

String _why(CFunction function) {
  if (function.parameters.isEmpty) return 'takes a callback or nothing';
  for (final parameter in function.parameters) {
    if (map(parameter.type) == null && !parameter.isHandleOut) {
      return 'parameter ${parameter.name} is ${parameter.type}';
    }
  }
  return 'returns ${function.returns}';
}

/// One method, or null when something about it is not understood.
String? _wrap(CFunction function, String owner, String dartName) {
  final parameters = function.parameters;
  if (parameters.isEmpty) return null;

  // Which parameter is the receiver, and which is the result.
  final selfIndex = parameters.indexWhere(
    (p) => p.pointee == owner && !p.isHandleOut,
  );
  final out = parameters.isNotEmpty && _isOut(parameters.last)
      ? parameters.last
      : null;

  final isFactory = function.name.startsWith('OgaCreate') &&
      out != null &&
      out.pointee == owner;
  if (!isFactory && selfIndex < 0) return null;

  final arguments = <String>[];
  final signature = <String>[];
  final prologue = <String>[];

  for (var i = 0; i < parameters.length; i++) {
    final parameter = parameters[i];
    if (parameter == out) continue;

    // A pointer followed by a count is one list. Upstream passes arrays that
    // way throughout, and handing a caller a Pointer and a length separately
    // would be handing them the C API back.
    final list = _asList(parameters, i);
    if (list != null) {
      final name = _dartParameterName(parameter.name);
      signature.add('${list.dart} $name');
      prologue.add(list.setUp(name));
      arguments.add('${name}Native');
      arguments.add('$name.length');
      i++; // The count is consumed with it.
      continue;
    }
    if (!isFactory && i == selfIndex) {
      arguments.add('handle');
      continue;
    }
    if (isFactory && parameter.pointee == owner && !parameter.isHandleOut) {
      return null; // A copy constructor, which needs a decision we should make.
    }

    final mapped = map(parameter.type);
    if (mapped == null) return null;
    final name = _dartParameterName(parameter.name);
    if (mapped.isString) {
      signature.add('String $name');
      arguments.add('cString(arena, $name)');
    } else if (mapped.isHandle) {
      signature.add('${mapped.dart} $name');
      arguments.add('$name.handle');
    } else {
      signature.add('${mapped.dart} $name');
      arguments.add(name);
    }
  }

  if (isFactory) {
    final named = function.name.substring('OgaCreate'.length);
    final constructor = named == dartName
        ? 'factory $dartName'
        : 'factory $dartName.${_lowerFirst(named.substring(dartName.length))}';
    return '''
  /// Wraps `${function.name}`.
  $constructor(${signature.join(', ')}) => withArena((arena) {
        final out = arena<Pointer<$owner>>();
        check(${function.name}(${[...arguments, 'out'].join(', ')}));
        return $dartName._(out.value);
      });
''';
  }

  final name = _methodName(function, owner);

  if (!function.canFail) {
    final returned = map(function.returns);
    if (returned == null) return null;
    final call = '${function.name}(${arguments.join(', ')})';
    if (returned.dart == 'void') {
      return '''
  /// Wraps `${function.name}`.
  void $name(${signature.join(', ')}) =>
      ${signature.isEmpty ? call : 'withArena((arena) => $call)'};
''';
    }
    return '''
  /// Wraps `${function.name}`.
  ${returned.dart} $name(${signature.join(', ')}) =>
      ${signature.isEmpty ? call : 'withArena((arena) => $call)'};
''';
  }

  if (out == null) {
    return '''
  /// Wraps `${function.name}`.
  void $name(${signature.join(', ')}) => withArena((arena) {
${prologue.map((l) => '        $l').join('\n')}${prologue.isEmpty ? '' : '\n'}        check(${function.name}(${arguments.join(', ')}));
      });
''';
  }

  // A result to read back out of native memory.
  final produced = out.isHandleOut ? out.pointee : null;
  if (produced != null && produced.startsWith('Oga')) {
    return '''
  /// Wraps `${function.name}`.
  ${dartNameOf(produced)} $name(${signature.join(', ')}) => withArena((arena) {
        final out = arena<Pointer<$produced>>();
        check(${function.name}(${[...arguments, 'out'].join(', ')}));
        return ${dartNameOf(produced)}._(out.value);
      });
''';
  }

  final scalar = map(out.type.replaceFirst('*', ''));
  if (scalar == null) return null;
  if (scalar.isString) {
    return '''
  /// Wraps `${function.name}`.
  String $name(${signature.join(', ')}) => withArena((arena) {
        final out = arena<Pointer<Char>>();
        check(${function.name}(${[...arguments, 'out'].join(', ')}));
        return takeCString(out.value);
      });
''';
  }
  const native = {'int': 'Size', 'bool': 'Bool', 'double': 'Double'};
  final slot = native[scalar.dart];
  if (slot == null) return null;
  return '''
  /// Wraps `${function.name}`.
  ${scalar.dart} $name(${signature.join(', ')}) => withArena((arena) {
        final out = arena<$slot>();
        check(${function.name}(${[...arguments, 'out'].join(', ')}));
        return out.value;
      });
''';
}

/// A function that takes no handle, wrapped as a top level function.
String? _free(CFunction function) {
  final out = function.parameters.isNotEmpty && _isOut(function.parameters.last)
      ? function.parameters.last
      : null;

  final arguments = <String>[];
  final signature = <String>[];
  for (final parameter in function.parameters) {
    if (parameter == out) continue;
    final mapped = map(parameter.type);
    if (mapped == null) return null;
    final name = _lowerFirst(parameter.name
        .split('_')
        .map((p) => p.isEmpty ? p : p[0].toUpperCase() + p.substring(1))
        .join());
    signature.add('${mapped.dart} $name');
    arguments.add(mapped.isString
        ? 'cString(arena, $name)'
        : mapped.isHandle
            ? '$name.handle'
            : name);
  }

  final name = _lowerFirst(function.name.substring(3));
  final call = '${function.name}(${arguments.join(', ')})';

  if (!function.canFail) {
    final returned = map(function.returns);
    if (returned == null) return null;
    final body = signature.isEmpty ? call : 'withArena((arena) => $call)';
    return '''
/// Wraps `${function.name}`.
${returned.dart} $name(${signature.join(', ')}) => $body;
''';
  }

  if (out == null) {
    return '''
/// Wraps `${function.name}`.
void $name(${signature.join(', ')}) => withArena((arena) {
      check($call);
    });
''';
  }

  final scalar = map(out.type.replaceFirst('*', ''));
  if (scalar == null) return null;
  const native = {'int': 'Size', 'bool': 'Bool', 'double': 'Double'};
  final slot = native[scalar.dart];
  if (slot == null) return null;
  return '''
/// Wraps `${function.name}`.
${scalar.dart} $name(${signature.join(', ')}) => withArena((arena) {
      final out = arena<$slot>();
      check(${function.name}(${[...arguments, 'out'].join(', ')}));
      return out.value;
    });
''';
}

String _globalsFile(String body) => '''
// AUTO GENERATED FILE, DO NOT EDIT.
//
// Generated from third_party/onnxruntime-genai/src/ort_genai_c.h.
// Regenerate with `dart run tool/generate_bindings.dart` from this package.
//
// The functions that belong to no handle: logging, telemetry, the process wide
// device selection, and provider registration.

import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../bindings/genai_bindings.g.dart';
import 'support.dart';

$body''';

String _file({
  required String owner,
  required String dartName,
  required String destructor,
  required String body,
}) =>
    '''
// AUTO GENERATED FILE, DO NOT EDIT.
//
// Generated from third_party/onnxruntime-genai/src/ort_genai_c.h.
// Regenerate with `dart run tool/generate_bindings.dart` from this package.

import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../bindings/genai_bindings.g.dart';
import 'support.dart';

/// Wraps the `$owner` handle.
final class $dartName extends GenAiHandle<$owner> {
  $dartName._(super.handle);

  @override
  void destroy(Pointer<$owner> handle) => $destructor(handle);

$body}
''';

/// Emits Dart wrappers for the C API.
///
/// Each function becomes a method that takes Dart values, allocates whatever
/// the call needs in an arena, checks the returned `OrtStatus`, and returns the
/// out-parameters. Ownership follows the SAL annotation: an `_Outptr_ OrtX**`
/// hands back an `OrtX` the caller must release, which is the rule rather than
/// a per-function decision.
library;

import 'c_api.dart';
import 'ffigen_api.dart';
import 'types.dart';

/// Groups functions into files, most specific pattern first.
const groups = <String, String>{
  'session':
      r'^(Create|Release|Clone)?Session|^Run$|RunAsync|RunWithBinding|Profiling',
  'options':
      r'SessionOptions|RunOptions|ThreadingOptions|ArenaCfg|SetGlobal|Env$|^CreateEnv|^ReleaseEnv',
  'tensor':
      r'Tensor|Value|Dimensions|^GetOnnxTypeFromTypeInfo|TypeInfo|MapType|SequenceType',
  'binding': r'IoBinding|^Bind',
  'memory': r'MemoryInfo|Allocator',
  'provider': r'Provider|EpDevice|ExecutionProvider|GetAvailable',
  'training': r'Training',
  'model': r'ModelMetadata|Metadata',
};

/// The file a function belongs in, or null to leave it out.
String? groupOf(String name) {
  for (final entry in groups.entries) {
    if (RegExp(entry.value).hasMatch(name)) return entry.key;
  }
  return null;
}

/// A Dart identifier from a C one: `SessionGetInputCount` to
/// `sessionGetInputCount`.
///
/// Member access is written `this.Name` because `package:ffi` exports
/// extensions that collide with struct member names.
String dartName(String name) => name[0].toLowerCase() + name.substring(1);

/// Emits the wrapper for [function], or null when it cannot be mapped.
///
/// [signature] is the same function as ffigen typed it, which is what the
/// emitted `asFunction` has to agree with.
String? emit(CFunction function, Signature signature) {
  if (!isFullyMapped(function)) return null;
  if (signature.length != function.parameters.length) return null;

  final inputs = <(CParameter, InputMapping)>[];
  final outputs = <(CParameter, OutputMapping)>[];
  for (final parameter in function.parameters) {
    switch (map(parameter)) {
      case final InputMapping m:
        inputs.add((parameter, m));
      case final OutputMapping m:
        outputs.add((parameter, m));
      case Unmapped():
        return null;
    }
  }

  // A scalar mapping leaves its Dart type to the signature, so that `bool` and
  // `double` are not mistaken for `int` on the way out.
  String typeOf(CParameter parameter, Mapping mapping) {
    final declared = switch (mapping) {
      InputMapping(:final dartType) ||
      OutputMapping(:final dartType) =>
        dartType,
      Unmapped() => null,
    };
    if (declared != null) return declared;
    final ffi = signature[function.parameters.indexOf(parameter)];
    return _callType(mapping is OutputMapping ? _pointee(ffi) : ffi);
  }

  final returnType = switch (outputs.length) {
    0 => 'void',
    1 => typeOf(outputs.single.$1, outputs.single.$2),
    _ => '(${outputs.map((o) => '${typeOf(o.$1, o.$2)} '
        '${_dartParam(o.$1.name)}').join(', ')})',
  };

  final parameters = inputs
      .map((i) => '${typeOf(i.$1, i.$2)} ${_dartParam(i.$1.name)}')
      .join(', ');

  // `asFunction` is typed with the Dart signature, so scalars cross as `int`
  // and `double` even though the field they come from is typed in FFI terms.
  final callSignature = signature.map(_callType).join(', ');

  // A release returns void and cannot fail, so it needs no arena and no status
  // check. Emitting the general shape for it would be noise around one call.
  if (!function.returnsStatus) {
    final argument = _dartParam(function.parameters.single.name);
    final type = _callType(signature.single);
    return '''  /// `${function.name}`
  void ${dartName(function.name)}($type $argument) =>
      this.${function.name}.asFunction<void Function($callSignature)>()($argument);
''';
  }

  final buffer = StringBuffer()
    ..writeln('  /// `${function.name}`')
    ..writeln('  $returnType ${dartName(function.name)}($parameters) =>')
    ..writeln('      withArena((arena) {');

  // An out-parameter is `Pointer<X>`, so `X` is what the arena allocates.
  for (final (index, (parameter, _)) in outputs.indexed) {
    final cell = _pointee(signature[function.parameters.indexOf(parameter)]);
    buffer.writeln('        final ${_out(index)} = arena<$cell>();');
  }

  final outputIndex = {
    for (final (index, (parameter, _)) in outputs.indexed)
      parameter.name: index,
  };
  final arguments = function.parameters.map((p) {
    final mapping = map(p);
    return mapping is OutputMapping
        ? _out(outputIndex[p.name]!)
        : (mapping as InputMapping).marshal(_dartParam(p.name));
  }).join(', ');

  buffer
    ..writeln('        checkOrtStatus(this.${function.name}')
    ..writeln('            .asFunction<')
    ..writeln('              Pointer<OrtStatus> Function($callSignature)')
    ..writeln('            >()($arguments));');

  switch (outputs.length) {
    case 0:
      break;
    case 1:
      buffer.writeln('        return ${outputs.single.$2.read(_out(0))};');
    default:
      final reads =
          outputs.indexed.map((e) => e.$2.$2.read(_out(e.$1))).join(', ');
      buffer.writeln('        return ($reads);');
  }

  buffer.writeln('      });');
  return buffer.toString();
}

/// Avoids colliding with Dart keywords and with our own locals.
String _dartParam(String name) {
  const reserved = {'in', 'out', 'is', 'default', 'this', 'new', 'var'};
  final camel = name
      .split('_')
      .indexed
      .map((e) =>
          e.$1 == 0 ? e.$2 : '${e.$2[0].toUpperCase()}${e.$2.substring(1)}')
      .join();
  return reserved.contains(camel) ? '${camel}_' : camel;
}

String _out(int index) => 'out$index';

/// The Dart-side spelling of an FFI type, for the `asFunction` signature.
String _callType(String ffiType) => switch (ffiType) {
      'Size' ||
      'Int' ||
      'Int32' ||
      'UnsignedInt' ||
      'Int64' ||
      'Uint64' =>
        'int',
      'Float' || 'Double' => 'double',
      'Bool' => 'bool',
      _ => ffiType,
    };

/// `X` from `Pointer<X>`.
String _pointee(String type) {
  if (!type.startsWith('Pointer<') || !type.endsWith('>')) {
    throw StateError('out-parameter is not a pointer: $type');
  }
  return type.substring('Pointer<'.length, type.length - 1);
}

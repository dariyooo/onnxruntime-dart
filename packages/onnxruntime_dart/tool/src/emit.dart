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
///
/// Filing only. Every function that can be wrapped is wrapped, so a name none
/// of these match lands in [_fallbackGroup] rather than being dropped.
const groups = <String, String>{
  'kernel': r'Kernel|CustomOp|ShapeInfer|^Op$|^Op[A-Z]|OpAttr|^InvokeOp',
  'graph': r'^Graph$|^Graph_|^Node$|^Node_|ValueInfo|^Model_|^OpaqueValue|'
      r'Initializer',
  'ep': r'^Ep[A-Z_]|EpFactory|EpGraph|EpDevice|NodeCompute|HardwareDevice|'
      r'DeviceEp|SyncStream|^RegisterExecutionProvider|^UnregisterExecutionProvider',
  'training': r'Training|Lora|Adapter',
  'sparse': r'Sparse|DLPack|TuningResult|^Use(Coo|Csr|Block)',
  'binding': r'IoBinding|^Bind|^ClearBound|^GetBound|^SynchronizeBound',
  'memory': r'MemoryInfo|Allocator|Arena|MemPattern|^CreateAndRegister|'
      r'PrepackedWeights',
  'session':
      r'^(Create|Release|Clone)?Session|^Run$|RunAsync|RunWithBinding|Profiling',
  'options':
      r'SessionOptions|RunOptions|ThreadingOptions|SetGlobal|ConfigEntry|'
          r'FreeDimensionOverride|Env$|^CreateEnv|^ReleaseEnv|^Enable|^Disable|'
          r'^SetSession|^SetInter|^SetIntra|^SetDeterministic|^SetOptimized|'
          r'^SetLanguageProjection|^SetGlobal|^SetEp|^SetLoad|^SetCurrentGpu|'
          r'^UpdateEnv|PerSessionThreadPool|SessionExecutionMode',
  'tensor': r'Tensor|Value|Dimensions|Symbolic|TypeInfo|MapType|MapKeyType|'
      r'SequenceType|SequenceElementType|OnnxType',
  'provider': r'Provider|ExecutionProvider|GetAvailable|Compat',
  'model': r'ModelMetadata|Metadata|^Compile|^Model',
  'status': r'^GetErrorCode|^GetErrorMessage|^CreateStatus|^ReleaseStatus|'
      r'Logger|^Log$|Telemetry',
};

/// Where a function lands when no pattern claims it.
const _fallbackGroup = 'core';

/// The file a function belongs in.
///
/// A release files with the type it releases, so `ReleaseGraph` sits next to
/// the graph calls rather than wherever its own name happens to match.
String groupOf(String name) {
  final released = RegExp(r'^Release(\w+)$').firstMatch(name)?.group(1);
  return _match(released) ?? _match(name) ?? _fallbackGroup;
}

String? _match(String? name) {
  if (name == null) return null;
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
///
/// Listed rather than inferred, and unknown types throw: a width guessed wrong
/// here produces Dart that analyzes cleanly and fails to compile, so failing at
/// generation time is the cheaper place to find out.
String _callType(String ffiType) {
  if (ffiType.startsWith('Pointer<')) return ffiType;
  return switch (ffiType) {
    'Int8' ||
    'Int16' ||
    'Int32' ||
    'Int64' ||
    'Uint8' ||
    'Uint16' ||
    'Uint32' ||
    'Uint64' ||
    'IntPtr' ||
    'UintPtr' ||
    'Char' ||
    'SignedChar' ||
    'UnsignedChar' ||
    'Short' ||
    'UnsignedShort' ||
    'Int' ||
    'UnsignedInt' ||
    'Long' ||
    'UnsignedLong' ||
    'LongLong' ||
    'UnsignedLongLong' ||
    'Size' ||
    'WChar' =>
      'int',
    'Float' || 'Double' => 'double',
    'Bool' => 'bool',
    _ => throw StateError('no Dart type for the FFI type $ffiType'),
  };
}

/// `X` from `Pointer<X>`.
String _pointee(String type) {
  if (!type.startsWith('Pointer<') || !type.endsWith('>')) {
    throw StateError('out-parameter is not a pointer: $type');
  }
  return type.substring('Pointer<'.length, type.length - 1);
}

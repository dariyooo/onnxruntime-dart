/// Maps C types to Dart.
///
/// Every mapping is a rule, not a table of function names: the header is
/// regular enough that a type plus its SAL direction determines the Dart shape.
/// Anything not covered here is reported rather than guessed at, so the
/// generator's coverage is a number rather than a hope.
library;

import 'c_api.dart';

/// How one C parameter appears in Dart.
sealed class Mapping {
  const Mapping();
}

/// A Dart parameter, marshalled in.
final class InputMapping extends Mapping {
  const InputMapping(this.dartType, this.marshal);

  /// A scalar passed straight through, whose Dart type the ffigen signature
  /// decides: `int`, `double` or `bool`, depending on the C type's width.
  const InputMapping.scalar()
      : dartType = null,
        marshal = _identity;

  /// Null when the ffigen signature decides.
  final String? dartType;

  /// Dart expression producing the C argument, given the parameter name.
  final String Function(String name) marshal;
}

String _identity(String name) => name;

/// Part of the return value, read out of an out-parameter.
final class OutputMapping extends Mapping {
  const OutputMapping(this.dartType, this.read);

  /// A scalar read back, typed from the ffigen signature.
  const OutputMapping.scalar()
      : dartType = null,
        read = _readValue;

  /// Null when the ffigen signature decides.
  final String? dartType;

  /// Dart expression reading the result, given the allocated pointer name.
  final String Function(String pointer) read;
}

String _readValue(String pointer) => '$pointer.value';

/// Nothing here understands this parameter yet.
final class Unmapped extends Mapping {
  const Unmapped(this.reason);
  final String reason;
}

/// An ONNX Runtime handle, such as `OrtSession*`.
final _handle = RegExp(r'^(?:const\s+)?(Ort\w+)\s*\*$');

/// A pointer to a handle, such as `OrtSession**`, which is how they come back.
final _handleOut = RegExp(r'^(?:const\s+)?(Ort\w+)\s*\*\s*\*$');

/// C enums, which cross as their underlying integer.
///
/// ffigen emits Dart enums for these, but the function pointers take the raw
/// value, so the boundary deals in ints and the typed enum sits above it.
const _enums = {
  'OrtLoggingLevel',
  'ONNXTensorElementDataType',
  'ONNXType',
  'OrtAllocatorType',
  'OrtMemType',
  'OrtDeviceMemoryType',
  'OrtErrorCode',
  'OrtSparseFormat',
  'GraphOptimizationLevel',
  'ExecutionMode',
  'OrtLanguageProjection',
  'OrtHardwareDeviceType',
  'OrtExecutionProviderDevicePolicy',
  'OrtCompiledModelFormat',
};

/// C scalars that cross as a Dart primitive. Which primitive, and how wide, is
/// the ffigen signature's call rather than this list's.
const _scalars = {
  'size_t',
  'int',
  'int32_t',
  'uint32_t',
  'int64_t',
  'uint64_t',
  'float',
  'double',
  'bool',
};

/// Maps [parameter], or explains why it cannot.
Mapping map(CParameter parameter) {
  // `struct OrtAllocator*` and `OrtAllocator*` are the same thing.
  final type = parameter.type
      .replaceAll(RegExp(r'\bstruct\s+'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  if (parameter.direction == Direction.output) return _mapOutput(type);
  return _mapInput(type, parameter);
}

Mapping _mapInput(String type, CParameter parameter) {
  // Paths are ORTCHAR_T, which is UTF-16 on Windows.
  if (type.contains('ORTCHAR_T')) {
    return InputMapping('String', (n) => 'allocateOrtPath($n, arena)');
  }
  if (type == 'const char*') {
    return InputMapping(
      'String',
      (n) => '$n.toNativeUtf8(allocator: arena).cast()',
    );
  }
  if (type == 'const char* const*') {
    return InputMapping('List<String>', (n) => 'nativeStrings($n, arena)');
  }
  if (_scalars.contains(type)) return const InputMapping.scalar();
  if (_enums.contains(_bareEnum(type))) return const InputMapping.scalar();
  // Integer arrays, always paired with a length parameter the caller passes.
  if (type == 'const int64_t*' || type == 'int64_t*') {
    return InputMapping('List<int>', (n) => 'nativeInt64s($n, arena)');
  }
  if (type == 'const size_t*' || type == 'size_t*') {
    return InputMapping('List<int>', (n) => 'nativeSizes($n, arena)');
  }
  if (type == 'void*' || type == 'const void*') {
    return InputMapping('Pointer<Void>', (n) => n);
  }
  final handle = _handle.firstMatch(type);
  if (handle != null) {
    return InputMapping('Pointer<${handle.group(1)}>', (n) => n);
  }
  // An array of handles, as Run takes for its inputs and outputs. The const
  // qualifiers vary, so match on the handle name rather than the exact spelling.
  final handles = RegExp(
    r'^(?:const\s+)?(Ort\w+)\s*\*(?:\s*const)?\s*\*$',
  ).firstMatch(type);
  if (handles != null) {
    return InputMapping(
      'List<Pointer<${handles.group(1)}>>',
      (n) => 'nativePointers($n, arena)',
    );
  }
  return Unmapped('input $type');
}

String _bareEnum(String type) =>
    type.replaceFirst(RegExp(r'^(?:const\s+)?enum\s+'), '').trim();

Mapping _mapOutput(String type) {
  final bare = _bareEnum(type.replaceFirst(RegExp(r'\s*\*$'), ''));
  if (type.endsWith('*') && _enums.contains(bare)) {
    return const OutputMapping.scalar();
  }
  // Runtime-owned, unlike char** which comes from the allocator and must be
  // freed. Reading it is enough.
  if (type == 'const char**') {
    return OutputMapping(
      'String',
      (p) => '$p.value.cast<Utf8>().toDartString()',
    );
  }
  if (type == 'char**') {
    // Allocator memory. Reading it is not enough, it has to be freed.
    return OutputMapping('String', (p) => 'takeAllocatedString($p)');
  }
  if (type.endsWith('*') &&
      _scalars.contains(type.replaceFirst(RegExp(r'\s*\*$'), ''))) {
    return const OutputMapping.scalar();
  }
  final handle = _handleOut.firstMatch(type);
  if (handle != null) {
    return OutputMapping('Pointer<${handle.group(1)}>', (p) => '$p.value');
  }
  if (type == 'void**') {
    return OutputMapping('Pointer<Void>', (p) => '$p.value');
  }
  return Unmapped('output $type');
}

/// Whether every parameter of [function] maps.
bool isFullyMapped(CFunction function) =>
    function.parameters.every((p) => map(p) is! Unmapped);

/// Why [function] cannot be generated, empty when it can.
List<String> unmappedReasons(CFunction function) => [
      for (final p in function.parameters)
        if (map(p) case Unmapped(:final reason)) reason,
    ];

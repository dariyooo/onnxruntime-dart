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
  const OutputMapping(
    this.dartType,
    this.read, {
    this.needsAllocator = false,
    this.readArray,
  });

  /// A scalar read back, typed from the ffigen signature.
  const OutputMapping.scalar()
      : dartType = null,
        needsAllocator = false,
        readArray = null,
        read = _readValue;

  /// Null when the ffigen signature decides.
  final String? dartType;

  /// Whether reading frees allocator memory, so the emitter has to say which
  /// allocator the call was given rather than assuming the default one.
  final bool needsAllocator;

  /// Dart expression reading the result, given the allocated pointer name.
  final String Function(String pointer) read;

  /// Reads the whole array at once, for an array the call allocated rather
  /// than one it filled in place.
  ///
  /// Null for the ordinary case, where walking the buffer element by element
  /// is all it takes. Set where the array has to be freed as well as read, so
  /// that per-element reading would have nowhere to put the free.
  final String Function(String pointer, String count)? readArray;

  /// Dart expression reading [count] results, for a parameter the call writes
  /// an array into.
  String readAll(String pointer, String count) =>
      'List.generate($count, (i) => ${read('($pointer + i)')})';
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

  if (parameter.direction == Direction.output) {
    return _mapOutput(type, parameter);
  }
  return _mapInput(type, parameter);
}

/// A pointer to a scalar, such as `int64_t*` or `size_t*`.
final _scalarPointer = RegExp(r'^(?:const\s+)?(\w+)\s*\*$');

Mapping _mapInput(String type, CParameter parameter) {
  // `_Inout_` on a scalar pointer means one of two things the header does not
  // distinguish, and both break if it is marshalled as a plain input.
  //
  // Either the call writes the value back, as `_Inout_ size_t* size` does in
  // the ask-then-fill pattern, and an arena copy discards the answer. Or the
  // runtime keeps the buffer: `UseCooIndices` says "the life spans of the
  // buffers should eclipse the life span of this OrtValue", and an arena frees
  // it as the call returns, leaving the tensor pointing at freed memory.
  //
  // Which one it is has to be read per function, so these are reported rather
  // than guessed at.
  if (parameter.direction == Direction.inout) {
    final pointee = _scalarPointer.firstMatch(type)?.group(1);
    if (pointee != null && _scalars.contains(pointee)) {
      return Unmapped('inout $type, which is written back or kept');
    }
  }

  // Paths are ORTCHAR_T, which is UTF-16 on Windows. An array of them needs
  // that encoding per element, so the two spellings are separated here: a
  // single star is one path, a double star is a list of them. Matching only on
  // the name would hand `AddExternalInitializersFromFiles` a single pointer
  // where it wants an array.
  if (type.contains('ORTCHAR_T')) {
    return type.replaceAll(RegExp(r'[^*]'), '').length > 1
        ? InputMapping('List<String>', (n) => 'nativeOrtPaths($n, arena)')
        : InputMapping('String', (n) => 'allocateOrtPath($n, arena)');
  }
  if (type == 'const char*') {
    return InputMapping(
      'String',
      (n) => '$n.toNativeUtf8(allocator: arena).cast()',
    );
  }
  // An array of C strings, in any of the spellings the header uses:
  // `const char* const*`, `char* const*`, `const char**`. A const anywhere is
  // what marks it as one. Bare `char**` is left alone because it is an out
  // parameter as often as an array, and ReleaseAvailableProviders takes one to
  // free rather than to read.
  if (RegExp(r'^(?:const\s+)?char\s*\*\s*const\s*\*$').hasMatch(type) ||
      type == 'const char**') {
    return InputMapping('List<String>', (n) => 'nativeStrings($n, arena)');
  }
  // An enum crosses as its underlying integer: the function pointer takes the
  // raw value, and the typed enum sits above this boundary.
  // `const int64_t` is `int64_t`. Const on a value parameter says nothing
  // about the call, only that the callee will not reassign its own copy, so it
  // is dropped here. On a pointer it does mean something, which is why this
  // only strips it once the type is known to have no star.
  final value = type.startsWith('const ') && !type.contains('*')
      ? type.substring('const '.length)
      : type;

  if (_scalars.contains(value) || parameter.isEnum) {
    return const InputMapping.scalar();
  }
  // Integer arrays, always paired with a length parameter the caller passes.
  if (type == 'const int64_t*' || type == 'int64_t*') {
    return InputMapping('List<int>', (n) => 'nativeInt64s($n, arena)');
  }
  if (type == 'const int32_t*') {
    return InputMapping('List<int>', (n) => 'nativeInt32s($n, arena)');
  }
  if (type == 'const int*') {
    return InputMapping('List<int>', (n) => 'nativeInts($n, arena)');
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

Mapping _mapOutput(String type, CParameter parameter) {
  if (type.endsWith('*') && parameter.isEnum) {
    return const OutputMapping.scalar();
  }
  // Runtime-owned, unlike char** which comes from the allocator and must be
  // freed. Reading it is enough.
  // A trailing `const` qualifies the pointer, not what it points at, so it
  // makes no difference to how the value is read.
  final normalised = type.replaceFirst(RegExp(r'\s*const$'), '');
  // Runtime-owned like `const char**`, but read with the platform's path
  // encoding rather than as UTF-8.
  if (normalised == 'const ORTCHAR_T**' || normalised == 'ORTCHAR_T**') {
    return OutputMapping('String', (p) => 'readOrtPath($p.value)');
  }
  if (normalised == 'const char**') {
    return OutputMapping(
      'String',
      (p) => '$p.value.cast<Utf8>().toDartString()',
    );
  }
  if (normalised == 'char**') {
    // Allocator memory. Reading it is not enough, it has to be freed, and with
    // the allocator that produced it rather than whichever is the default.
    return OutputMapping(
      'String',
      (p) => 'takeAllocatedString($p, ALLOCATOR)',
      needsAllocator: true,
    );
  }
  if (type.endsWith('*') &&
      _scalars.contains(type.replaceFirst(RegExp(r'\s*\*$'), ''))) {
    return const OutputMapping.scalar();
  }
  // `_Outptr_ X** items, _Out_ size_t* count`: the call allocates the array
  // and says how long it is, so the arena holds one pointer cell and the
  // elements are read from what came back. Guarded on both marks, because the
  // same spelling caller-allocated is a buffer to fill, and callee-allocated
  // without a count is a single handle.
  if (parameter.isCalleeAllocated && parameter.arrayLengthParameter != null) {
    if (normalised == 'char***') {
      return OutputMapping(
        'String',
        _readValue,
        needsAllocator: true,
        readArray: (p, n) => 'takeAllocatedStrings($p.value, $n, ALLOCATOR)',
      );
    }
    final elements = RegExp(
      r'^(?:const\s+)?(Ort\w+)\s*\*\s*(?:const\s*)?\*\s*\*$',
    ).firstMatch(normalised);
    if (elements != null) {
      return OutputMapping(
        'Pointer<${elements.group(1)}>',
        _readValue,
        readArray: (p, n) => 'List.generate($n, (i) => $p.value[i])',
      );
    }
    // A shape or similar, borrowed from the runtime: read, never freed.
    if (RegExp(r'^(?:const\s+)?(?:int64_t|size_t|int32_t|float)\*\*$')
        .hasMatch(normalised)) {
      return OutputMapping(
        normalised.contains('float') ? 'double' : 'int',
        _readValue,
        readArray: (p, n) => 'List.generate($n, (i) => $p.value[i])',
      );
    }
  }
  final handle = _handleOut.firstMatch(type);
  if (handle != null) {
    return OutputMapping('Pointer<${handle.group(1)}>', (p) => '$p.value');
  }
  if (normalised == 'void**' || normalised == 'const void**') {
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

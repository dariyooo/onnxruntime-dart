/// How a C type in the GenAI header becomes a Dart one.
///
/// Nothing here guesses. A type this does not know produces null, the function
/// using it is left out, and it is listed in unmapped.txt for someone to look
/// at. Emitting a wrapper that compiles but lies about ownership would be
/// worse than not emitting one.
library;

/// A C type mapped onto both sides of the FFI boundary.
final class Mapped {
  const Mapped({
    required this.ffi,
    required this.dart,
    this.isHandle = false,
    this.isString = false,
  });

  /// The type in the generated ffigen bindings.
  final String ffi;

  /// The type the wrapper offers.
  final String dart;

  /// Whether this is an opaque GenAI handle rather than a value.
  final bool isHandle;

  /// Whether this is a C string, which has to be copied into the arena on the
  /// way in and read back out on the way out.
  final bool isString;
}

/// GenAI's enums, which cross as the integers they are.
///
/// The header declares one. It is passed by value and returned through an out
/// parameter, and both are the same width as an int32.
const _enums = {'OgaElementType'};

const _scalars = <String, Mapped>{
  'bool': Mapped(ffi: 'bool', dart: 'bool'),
  'int32_t': Mapped(ffi: 'int', dart: 'int'),
  'int64_t': Mapped(ffi: 'int', dart: 'int'),
  'uint32_t': Mapped(ffi: 'int', dart: 'int'),
  'size_t': Mapped(ffi: 'int', dart: 'int'),
  // Plain int, which the GPU device functions use where the rest of the
  // header is explicit about width.
  'int': Mapped(ffi: 'int', dart: 'int'),
  'float': Mapped(ffi: 'double', dart: 'double'),
  'double': Mapped(ffi: 'double', dart: 'double'),
  'void': Mapped(ffi: 'void', dart: 'void'),
};

/// The Dart form of [type], or null when it is not one we translate.
Mapped? map(String type) {
  final bare = type.replaceAll('const ', '').replaceAll(' ', '');

  if (bare == 'char*') {
    return const Mapped(ffi: 'Pointer<Char>', dart: 'String', isString: true);
  }
  if (_scalars.containsKey(bare)) return _scalars[bare];
  if (_enums.contains(bare)) return const Mapped(ffi: 'int', dart: 'int');

  // OgaResult is how the C API reports failure, not something a caller holds.
  // support.dart reads it and releases it inside check(), so wrapping it would
  // offer an error object nobody should ever be handed.
  if (bare.startsWith('OgaResult')) return null;

  // An opaque handle. One star is the handle itself; two is an out-parameter
  // the caller owns afterwards, which the emitter handles rather than this.
  if (bare.startsWith('Oga') && bare.endsWith('*')) {
    final name = bare.replaceAll('*', '');
    return Mapped(
      ffi: 'Pointer<$name>',
      dart: dartNameOf(name),
      isHandle: true,
    );
  }
  return null;
}

/// The Dart class name for a GenAI handle type.
///
/// `OgaGeneratorParams` reads as `GeneratorParams` in Dart: the prefix is there
/// to keep C's single namespace apart, and Dart has libraries for that.
String dartNameOf(String handle) =>
    handle.startsWith('Oga') ? handle.substring(3) : handle;

/// Whether [type] is an opaque handle rather than a value.
bool isHandle(String type) {
  final bare = type.replaceAll('const ', '').replaceAll('*', '').trim();
  return bare.startsWith('Oga') && bare != 'OgaResult';
}

/// The dart:ffi type an out-parameter of C type [type] is read through.
///
/// Taken from the C type rather than from the Dart one it maps to. Every
/// integer here is `int` in Dart, and allocating a size_t to receive an
/// int32_t writes the wrong number of bytes.
String? nativeSlot(String type) {
  final bare = type.replaceAll('const ', '').replaceAll(' ', '');
  // ffigen types a C enum as unsigned int, so the slot has to match what the
  // binding declares rather than what the values happen to fit in.
  if (_enums.contains(bare)) return 'UnsignedInt';
  return switch (bare) {
    'size_t' => 'Size',
    'int32_t' => 'Int32',
    'int64_t' => 'Int64',
    'uint32_t' => 'Uint32',
    'int' => 'Int',
    'bool' => 'Bool',
    'float' => 'Float',
    'double' => 'Double',
    _ => null,
  };
}

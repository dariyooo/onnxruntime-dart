/// Marshalling for ORTCHAR_T, the type ONNX Runtime uses for filesystem paths.
///
/// ORTCHAR_T is `wchar_t` on Windows and `char` everywhere else, so its width
/// changes with the platform. ffigen resolves it against whichever platform
/// generated the bindings, which means the committed `Pointer<Char>` signature
/// is wrong on Windows. A pointer is only an address, so the declared pointee
/// does not matter at the ABI level and the encoding is decided here instead.
///
/// Sixteen C functions take ORTCHAR_T, including `SetOptimizedModelFilePath`,
/// `EnableProfiling`, `RegisterCustomOpsLibrary` and
/// `AddExternalInitializersFromFilesInMemory`. Sessions are always created from
/// bytes, so `CreateSession` is not among the ones we call.
library;

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// Whether ORTCHAR_T is 16 bits wide here.
bool get ortPathIsWide => Platform.isWindows;

/// Bytes per ORTCHAR_T.
int get ortPathUnitBytes => ortPathIsWide ? 2 : 1;

/// Allocates a NUL-terminated ORTCHAR_T copy of [path]. The caller frees it.
Pointer<Char> allocateOrtPath(String path, Allocator allocator) =>
    encodeOrtPath(path, allocator, wide: ortPathIsWide);

/// Reads a NUL-terminated ORTCHAR_T string.
String readOrtPath(Pointer<Char> pointer) =>
    decodeOrtPath(pointer, wide: ortPathIsWide);

/// [allocateOrtPath] with the platform choice made explicit.
///
/// Both encodings stay reachable on every platform so tests cover the branch
/// that does not apply locally.
Pointer<Char> encodeOrtPath(
  String path,
  Allocator allocator, {
  required bool wide,
}) {
  if (!wide) return path.toNativeUtf8(allocator: allocator).cast<Char>();

  // Dart strings are already UTF-16, which is what wchar_t holds on Windows.
  final units = path.codeUnits;
  final buffer = allocator<Uint16>(units.length + 1);
  buffer.asTypedList(units.length + 1)
    ..setRange(0, units.length, units)
    ..[units.length] = 0;
  return buffer.cast<Char>();
}

/// [readOrtPath] with the platform choice made explicit.
String decodeOrtPath(Pointer<Char> pointer, {required bool wide}) {
  if (!wide) return pointer.cast<Utf8>().toDartString();

  final units = pointer.cast<Uint16>();
  var length = 0;
  while (units[length] != 0) {
    length++;
  }
  return String.fromCharCodes(units.asTypedList(length));
}

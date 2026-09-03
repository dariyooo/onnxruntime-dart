/// Marshalling the generated wrappers rely on.
///
/// Hand-written because it is the same for every call, and because the parts
/// that matter are the ones a generator should not invent: who owns what, and
/// when it is freed.
library;

import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../../ffi/runtime.dart';
import '../../ffi/status.dart';
import '../ort_bindings.g.dart';

export '../../ffi/ort_path.dart'
    show allocateOrtPath, nativeOrtPaths, readOrtPath;

/// The `OrtApi` used to read and release an `OrtStatus`.
///
/// Resolved on first use. A status can only be read through the API that
/// produced it, and the generated wrappers are extensions on `OrtApi` rather
/// than methods holding one, so this is how they reach it.
final OrtApi ortApiForStatus = ortApi().ref;

/// Runs [body] with an arena, releasing it on every path.
///
/// Everything a call needs is scoped to the call: ONNX Runtime copies the
/// strings and arrays it is handed, so nothing here outlives it. Tensors are
/// the exception, and they are not built this way.
T withArena<T>(T Function(Arena arena) body) {
  final arena = Arena();
  try {
    return body(arena);
  } finally {
    arena.releaseAll();
  }
}

/// Throws if [status] is an error, releasing it either way.
void checkOrtStatus(Pointer<OrtStatus> status) =>
    checkStatus(ortApiForStatus, status);

/// Writes an array of strings, returning the `char**`.
Pointer<Pointer<Char>> nativeStrings(List<String> values, Arena arena) {
  final array = arena<Pointer<Char>>(values.isEmpty ? 1 : values.length);
  for (var i = 0; i < values.length; i++) {
    array[i] = values[i].toNativeUtf8(allocator: arena).cast();
  }
  return array;
}

/// Writes an array of handles, returning the `T**`.
///
/// Allocated as `Pointer<Void>` because Arena cannot allocate a type variable,
/// then cast. Every pointer is the same width, so the cast is safe.
Pointer<Pointer<T>> nativePointers<T extends NativeType>(
  List<Pointer<T>> values,
  Arena arena,
) {
  final array = arena<Pointer<Void>>(values.isEmpty ? 1 : values.length)
      .cast<Pointer<T>>();
  for (var i = 0; i < values.length; i++) {
    array[i] = values[i];
  }
  return array;
}

/// Writes int64 values, which is how the C API takes shapes on every platform.
Pointer<Int64> nativeInt64s(List<int> values, Arena arena) {
  final array = arena<Int64>(values.isEmpty ? 1 : values.length);
  for (var i = 0; i < values.length; i++) {
    array[i] = values[i];
  }
  return array;
}

/// Writes int32 values, which the sparse tensor indices take.
Pointer<Int32> nativeInt32s(List<int> values, Arena arena) {
  final array = arena<Int32>(values.isEmpty ? 1 : values.length);
  for (var i = 0; i < values.length; i++) {
    array[i] = values[i];
  }
  return array;
}

/// Writes plain `int` values, which the model editor takes for opset versions.
///
/// `int` is 32 bits on every platform this builds for, so [Int] and [Int32]
/// agree, but the header says `int` and the binding follows the header.
Pointer<Int> nativeInts(List<int> values, Arena arena) {
  final array = arena<Int>(values.isEmpty ? 1 : values.length);
  for (var i = 0; i < values.length; i++) {
    array[i] = values[i];
  }
  return array;
}

/// Writes `size_t` values.
Pointer<Size> nativeSizes(List<int> values, Arena arena) {
  final array = arena<Size>(values.isEmpty ? 1 : values.length);
  for (var i = 0; i < values.length; i++) {
    array[i] = values[i];
  }
  return array;
}

/// Reads an array of strings [allocator] owns, freeing the strings and the
/// array that held them.
///
/// `ModelMetadataGetCustomMetadataMapKeys` and
/// `KernelInfoGetAttributeArray_string` hand back both, so freeing only the
/// array leaks every key and freeing only the keys leaks the array.
List<String> takeAllocatedStrings(
  Pointer<Pointer<Char>> array,
  int count,
  Pointer<OrtAllocator> allocator,
) {
  final free = ortApiForStatus.AllocatorFree.asFunction<
      Pointer<OrtStatus> Function(Pointer<OrtAllocator>, Pointer<Void>)>();
  final values = [
    for (var i = 0; i < count; i++) array[i].cast<Utf8>().toDartString(),
  ];
  for (var i = 0; i < count; i++) {
    free(allocator, array[i].cast());
  }
  free(allocator, array.cast());
  return values;
}

/// Reads a string [allocator] owns, and frees it with the same allocator.
///
/// `SessionGetInputName` and its kin hand back memory the caller must return,
/// so reading without freeing leaks one name per call. Freeing it with a
/// different allocator than produced it is worse, which is why the allocator is
/// passed in rather than looked up.
String takeAllocatedString(
  Pointer<Pointer<Char>> out,
  Pointer<OrtAllocator> allocator,
) {
  final value = out.value.cast<Utf8>().toDartString();
  ortApiForStatus.AllocatorFree.asFunction<
      Pointer<OrtStatus> Function(
          Pointer<OrtAllocator>, Pointer<Void>)>()(allocator, out.value.cast());
  return value;
}

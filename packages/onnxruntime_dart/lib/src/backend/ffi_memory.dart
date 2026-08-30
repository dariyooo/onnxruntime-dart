/// [OrtMemory] over the C allocator.
library;

import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'interface.dart';
import 'types.dart';

/// Allocates with `malloc`, which is what ONNX Runtime's own allocations use,
/// so a buffer handed to it can be freed here.
final class FfiMemory implements OrtMemory {
  const FfiMemory();

  @override
  OrtPtr allocate(int byteCount) {
    if (byteCount <= 0) return OrtPtr.nullPtr;
    try {
      return OrtPtr(malloc.allocate<Uint8>(byteCount).address);
    } on Object {
      // The contract is a null pointer on failure, not an exception, because
      // the shared code checks the result either way.
      return OrtPtr.nullPtr;
    }
  }

  @override
  void free(OrtPtr pointer) {
    if (pointer.isNull) return;
    malloc.free(Pointer<Uint8>.fromAddress(pointer.address));
  }

  @override
  void write(OrtPtr destination, TypedData source) {
    if (destination.isNull) {
      throw ArgumentError('cannot write to a null pointer');
    }
    final bytes = Uint8List.view(
      source.buffer,
      source.offsetInBytes,
      source.lengthInBytes,
    );
    Pointer<Uint8>.fromAddress(destination.address)
        .asTypedList(bytes.length)
        .setAll(0, bytes);
  }

  @override
  Uint8List read(OrtPtr source, int byteCount) {
    if (source.isNull) {
      throw ArgumentError('cannot read from a null pointer');
    }
    if (byteCount < 0) {
      throw RangeError.value(byteCount, 'byteCount', 'must not be negative');
    }
    // Copies. A view would alias memory the caller may free.
    return Uint8List.fromList(
      Pointer<Uint8>.fromAddress(source.address).asTypedList(byteCount),
    );
  }
}

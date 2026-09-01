/// The Emscripten module ONNX Runtime's WebAssembly build produces.
///
/// Built with `MODULARIZE=1`, so the `.mjs` default-exports a factory that
/// returns a promise for the module. Everything reachable from it is fixed at
/// link time by two lists in `onnxruntime_webassembly.cmake`: `_malloc` and
/// `_free` plus every `EMSCRIPTEN_KEEPALIVE` function, and the runtime helpers
/// named here.
///
/// `FILESYSTEM=0`, which is why anything taking a path is unsupported rather
/// than merely unimplemented.
library;

import 'dart:js_interop';
import 'dart:typed_data';

/// The Emscripten module object, once its factory has resolved.
extension type OrtModule(JSObject _) implements JSObject {
  @JS('_malloc')
  external JSNumber allocate(JSNumber bytes);

  @JS('_free')
  external void release(JSNumber pointer);

  /// Reads a NUL-terminated UTF-8 string out of the heap.
  @JS('UTF8ToString')
  external JSString utf8ToString(JSNumber pointer);

  /// Writes [value] into the heap, including the NUL. [capacity] bounds it.
  @JS('stringToUTF8')
  external void stringToUtf8(
      JSString value, JSNumber pointer, JSNumber capacity);

  /// Bytes [value] needs, excluding the NUL.
  @JS('lengthBytesUTF8')
  external JSNumber lengthBytesUtf8(JSString value);

  /// Reads one value. [type] is an LLVM type name such as `i32` or `*`.
  external JSNumber getValue(JSNumber pointer, JSString type);

  external void setValue(JSNumber pointer, JSNumber value, JSString type);

  /// The heap itself. Detaches and is replaced whenever memory grows, so it is
  /// read fresh on every access rather than cached.
  @JS('HEAPU8')
  external JSUint8Array get heapU8;
}

/// A view of the module's heap that is safe to hold across an allocation.
///
/// `ALLOW_MEMORY_GROWTH=1` means any allocation can detach every existing
/// typed-data view, so nothing may keep one. This reads the current view each
/// time, which is the only correct way to touch the heap here.
extension OrtHeap on OrtModule {
  Uint8List get bytes => heapU8.toDart;

  int malloc(int size) {
    final pointer = allocate(size.toJS).toDartInt;
    if (pointer == 0) {
      throw StateError('the WebAssembly heap could not allocate $size bytes');
    }
    return pointer;
  }

  void free(int pointer) => release(pointer.toJS);

  /// Copies [data] into freshly allocated heap memory.
  int copyIn(TypedData data) {
    final source = Uint8List.view(
      data.buffer,
      data.offsetInBytes,
      data.lengthInBytes,
    );
    final pointer = malloc(source.lengthInBytes);
    bytes.setRange(pointer, pointer + source.lengthInBytes, source);
    return pointer;
  }

  /// Copies [length] bytes out of the heap at [pointer].
  Uint8List copyOut(int pointer, int length) =>
      Uint8List.fromList(bytes.sublist(pointer, pointer + length));

  /// Writes [value] as a NUL-terminated UTF-8 string.
  int allocateString(String value) {
    final size = lengthBytesUtf8(value.toJS).toDartInt + 1;
    final pointer = malloc(size);
    stringToUtf8(value.toJS, pointer.toJS, size.toJS);
    return pointer;
  }

  String readString(int pointer) => utf8ToString(pointer.toJS).toDart;

  /// One pointer-sized slot, zeroed, for a call that writes back.
  int allocateSlot([int count = 1]) {
    final pointer = malloc(4 * count);
    for (var i = 0; i < count; i++) {
      setValue((pointer + 4 * i).toJS, 0.toJS, 'i32'.toJS);
    }
    return pointer;
  }

  int readPointer(int slot) => getValue(slot.toJS, '*'.toJS).toDartInt;

  int readInt(int slot) => getValue(slot.toJS, 'i32'.toJS).toDartInt;
}

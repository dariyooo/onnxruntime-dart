/// Scratch heap memory with a scope, the way `Arena` works on native.
///
/// Every call into the runtime has to put its arguments somewhere: strings,
/// shapes, arrays of pointers, and slots for what the call writes back. All of
/// it is freed when the scope ends, including when the call threw.
library;

import 'dart:typed_data';

import 'module.dart';

class WasmArena {
  WasmArena(this._module);

  final OrtModule _module;
  final _owned = <int>[];

  int allocate(int bytes) => _keep(_module.malloc(bytes));

  int string(String value) => _keep(_module.allocateString(value));

  int data(TypedData value) => _keep(_module.copyIn(value));

  /// A zeroed slot per entry, for values the call writes back.
  int slots([int count = 1]) => _keep(_module.allocateSlot(count));

  /// An array of pointers, one per string, plus the strings themselves.
  int strings(List<String> values) =>
      words([for (final value in values) string(value)]);

  /// An array of handles.
  int handles(List<int> values) => words(values);

  /// Dimensions, which the wasm API takes as `size_t*`.
  int dimensions(List<int> shape) => words(shape);

  /// An array of 32-bit words, written in one pass.
  ///
  /// The heap view is taken after the allocation, never before: growing the
  /// heap detaches every existing view.
  int words(List<int> values) {
    final array = allocate(4 * values.length);
    final view = Uint32List.view(_module.bytes.buffer, array, values.length);
    view.setAll(0, values);
    return array;
  }

  int _keep(int pointer) {
    _owned.add(pointer);
    return pointer;
  }

  void releaseAll() {
    for (final pointer in _owned) {
      _module.free(pointer);
    }
    _owned.clear();
  }
}

/// Runs [body] with an arena, freeing everything it took afterwards.
T withArena<T>(OrtModule module, T Function(WasmArena) body) {
  final arena = WasmArena(module);
  try {
    return body(arena);
  } finally {
    arena.releaseAll();
  }
}

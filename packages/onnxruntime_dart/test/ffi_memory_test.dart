@TestOn('vm')

/// Everything above the backend boundary marshals through these four
/// operations, so a fault here is a fault everywhere.
library;

import 'dart:typed_data';

import 'package:onnxruntime_dart/src/backend/ffi_memory.dart';
import 'package:onnxruntime_dart/src/backend/types.dart';
import 'package:test/test.dart';

void main() {
  const memory = FfiMemory();

  group('allocate', () {
    test('returns a usable pointer', () {
      final p = memory.allocate(64);
      addTearDown(() => memory.free(p));
      expect(p.isNull, isFalse);
    });

    test('a non-positive size yields the null pointer, not a throw', () {
      // The contract is a null result, because callers check it either way.
      expect(memory.allocate(0), OrtPtr.nullPtr);
      expect(memory.allocate(-1), OrtPtr.nullPtr);
    });

    test('two allocations do not overlap', () {
      final a = memory.allocate(64);
      final b = memory.allocate(64);
      addTearDown(() {
        memory.free(a);
        memory.free(b);
      });
      expect(a.address, isNot(b.address));
    });
  });

  group('free', () {
    test('is a no-op on the null pointer', () {
      expect(() => memory.free(OrtPtr.nullPtr), returnsNormally);
    });
  });

  group('write and read', () {
    test('round trips bytes', () {
      final source = Uint8List.fromList([1, 2, 3, 4, 5]);
      final p = memory.allocate(source.length);
      addTearDown(() => memory.free(p));

      memory.write(p, source);
      expect(memory.read(p, source.length), source);
    });

    test('round trips a typed list of a wider element', () {
      final source = Float32List.fromList([1.5, -2.25, 3.0]);
      final p = memory.allocate(source.lengthInBytes);
      addTearDown(() => memory.free(p));

      memory.write(p, source);
      final back =
          Float32List.sublistView(memory.read(p, source.lengthInBytes));
      expect(back, source);
    });

    test('writes a view without dragging in the whole buffer', () {
      // A view's offsetInBytes is not zero, so writing must honour it rather
      // than copying from the start of the backing store.
      final backing = Uint8List.fromList([9, 9, 1, 2, 3, 9]);
      final view = Uint8List.sublistView(backing, 2, 5);
      final p = memory.allocate(view.length);
      addTearDown(() => memory.free(p));

      memory.write(p, view);
      expect(memory.read(p, 3), [1, 2, 3]);
    });

    test('read copies, so freeing the source does not corrupt it', () {
      final p = memory.allocate(4);
      memory.write(p, Uint8List.fromList([7, 7, 7, 7]));
      final copy = memory.read(p, 4);
      memory.free(p);

      expect(copy, [7, 7, 7, 7]);
    });

    test('refuses null pointers rather than corrupting memory', () {
      expect(
        () => memory.write(OrtPtr.nullPtr, Uint8List(1)),
        throwsArgumentError,
      );
      expect(() => memory.read(OrtPtr.nullPtr, 1), throwsArgumentError);
      expect(() => memory.read(memory.allocate(1), -1), throwsRangeError);
    });
  });

  group('under repetition', () {
    test('data survives many allocate, write, read, free cycles', () {
      // Catches an allocator that hands back memory still in use, which shows
      // up as one cycle reading another's bytes.
      for (var i = 0; i < 5000; i++) {
        final expected = Uint8List.fromList([i & 0xFF, (i >> 8) & 0xFF]);
        final p = memory.allocate(expected.length);
        memory.write(p, expected);
        expect(memory.read(p, expected.length), expected, reason: 'cycle $i');
        memory.free(p);
      }
    });
  });
}

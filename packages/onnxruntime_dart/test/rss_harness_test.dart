@TestOn('vm')
@Tags(['exclusive'])

/// Resident memory is a property of the whole process, and `dart test` runs
/// test files concurrently inside one. Another file allocating while these run
/// is indistinguishable from a leak, so they are tagged exclusive and run with
/// concurrency 1.
library;

import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:test/test.dart';

import 'src/memory_harness.dart';

void main() {
  group('measureRssGrowth', () {
    // A leak must touch its pages to be visible. Untouched pages do not count
    // toward resident memory.
    const chunkBytes = 1 << 20; // 1 MiB

    test('DELIBERATE LEAK: RSS growth is visible when memory is retained', () {
      final leaked = <Pointer<Uint8>>[];
      addTearDown(() {
        for (final pointer in leaked) {
          calloc.free(pointer);
        }
      });

      final measurement = measureRssGrowth(
        () {
          final pointer = calloc<Uint8>(chunkBytes);
          pointer.asTypedList(chunkBytes).fillRange(0, chunkBytes, 1);
          leaked.add(pointer);
        },
        iterations: 64,
        warmup: 4,
      );

      printOnFailure(measurement.toString());
      expect(
        measurement.growthBytes,
        greaterThan(32 * chunkBytes),
        reason: 'leaking 64 MiB must be visible. If this fails, the harness is '
            'measuring nothing and every other RSS assertion is void',
      );
    });

    test('balanced allocate/free does not register as growth', () {
      final measurement = measureRssGrowth(
        () {
          final pointer = calloc<Uint8>(chunkBytes);
          pointer.asTypedList(chunkBytes).fillRange(0, chunkBytes, 1);
          calloc.free(pointer);
        },
        iterations: 256,
        warmup: 16,
      );

      printOnFailure(measurement.toString());
      expect(
        measurement.growthBytes,
        lessThan(16 * chunkBytes),
        reason: 'freed memory must not accumulate. A failure here means the '
            'harness reports leaks where there are none',
      );
    });
  });
}

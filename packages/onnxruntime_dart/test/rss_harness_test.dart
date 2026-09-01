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

      var seed = 1;
      final measurement = measureRssGrowth(
        () {
          final pointer = calloc<Uint8>(chunkBytes);
          // Deliberately incompressible. Filling with one repeated byte lets
          // macOS compress the pages, and then a 64 MiB leak shows up as 30 MiB
          // of growth and this test fails while measuring correctly.
          final view = pointer.asTypedList(chunkBytes);
          for (var i = 0; i < chunkBytes; i++) {
            seed = (seed * 1103515245 + 12345) & 0x7fffffff;
            view[i] = seed >> 16;
          }
          leaked.add(pointer);
        },
        iterations: 64,
        warmup: 4,
      );

      printOnFailure(measurement.toString());
      // A quarter of what was leaked, not half. What this has to prove is
      // that the harness measures something real, so that the assertions built
      // on it mean anything. How much of a 64 MiB leak shows up as resident is
      // the operating system's business: the same code reports 64 MiB on Linux
      // and 29 MiB on a macOS runner, because pages can be compressed or
      // accounted differently. Demanding a specific fraction tests the
      // platform, not the harness.
      expect(
        measurement.growthBytes,
        greaterThan(16 * chunkBytes),
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

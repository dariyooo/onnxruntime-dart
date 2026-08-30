@TestOn('vm')

/// A harness that has never caught anything is not evidence, so every check is
/// exercised against a deliberate defect. A regression that silently disables
/// one fails here instead of passing everything.
library;

import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:test/test.dart';

import 'src/memory_harness.dart';

void main() {
  group('TrackingAllocator', () {
    test('reports clean when every allocation is freed', () {
      final allocator = TrackingAllocator(captureOrigins: false);
      for (var i = 0; i < 1000; i++) {
        allocator.free(allocator<Uint8>(128));
      }

      expect(allocator.report.isClean, isTrue);
      expect(allocator.report.liveAllocations, 0);
      expect(allocator.report.totalAllocations, 1000);
    });

    test('DELIBERATE LEAK: detects an allocation that is never freed', () {
      final allocator = TrackingAllocator();
      allocator<Uint8>(4096); // never freed, the defect under test

      final report = allocator.report;
      expect(report.isClean, isFalse);
      expect(report.liveAllocations, 1);
      expect(report.liveBytes, 4096);
      expect(report.origins, hasLength(1), reason: 'a leak must name its site');
      expect(report.toString(), contains('1 of 1 allocations leaked'));

      allocator.releaseAll();
      expect(allocator.report.isClean, isTrue);
    });

    test('origin capture can be disabled for hot loops', () {
      final allocator = TrackingAllocator(captureOrigins: false);
      allocator<Uint8>(8);

      expect(allocator.report.liveAllocations, 1);
      expect(allocator.report.origins, isEmpty);
      allocator.releaseAll();
    });

    test('DELIBERATE DEFECT: rejects a double free', () {
      final allocator = TrackingAllocator();
      final pointer = allocator<Uint8>(16);
      allocator.free(pointer);

      expect(
        () => allocator.free(pointer),
        throwsA(isA<StateError>()
            .having((e) => e.message, 'message', contains('already freed'))),
      );
    });

    test('DELIBERATE DEFECT: rejects freeing a foreign pointer', () {
      final allocator = TrackingAllocator();
      final foreign = calloc<Uint8>(8);
      addTearDown(() => calloc.free(foreign));

      expect(
        () => allocator.free(foreign),
        throwsA(isA<StateError>()
            .having((e) => e.message, 'message', contains('did not allocate'))),
      );
    });

    test('freeing nullptr is a no-op', () {
      final allocator = TrackingAllocator();
      expect(
          () => allocator.free(Pointer<Void>.fromAddress(0)), returnsNormally);
      expect(allocator.report.isClean, isTrue);
    });
  });
}

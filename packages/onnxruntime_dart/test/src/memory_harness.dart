/// Two independent leak checks for native memory.
///
/// [TrackingAllocator] is exact. It accounts for every allocation this package
/// makes and names the site of any that outlive their scope.
/// [measureRssGrowth] is heuristic and catches what the allocator cannot see,
/// meaning leaks inside ONNX Runtime and handles we allocate but never release.
///
/// `memory_harness_test.dart` proves each check fails on a deliberate defect.
///
/// No AddressSanitizer. It instruments a whole process and the released Dart VM
/// carries no ASan runtime, so an ASan target would report success while
/// checking nothing. Use `/usr/bin/leaks` on macOS until we build ORT ourselves.
library;

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

final class _LiveAllocation {
  _LiveAllocation(this.byteCount, this.origin);

  final int byteCount;

  /// Where the allocation happened, if capture is enabled.
  final StackTrace? origin;
}

/// What a [TrackingAllocator] still holds.
final class LeakReport {
  LeakReport({
    required this.liveAllocations,
    required this.liveBytes,
    required this.totalAllocations,
    required this.origins,
  });

  final int liveAllocations;
  final int liveBytes;

  /// Every allocation over the allocator's lifetime, freed or not.
  final int totalAllocations;

  /// Empty when [TrackingAllocator.captureOrigins] was off.
  final List<StackTrace> origins;

  bool get isClean => liveAllocations == 0;

  @override
  String toString() {
    if (isClean) {
      return 'no leaks ($totalAllocations allocations, all freed)';
    }
    final buffer = StringBuffer()
      ..writeln('$liveAllocations of $totalAllocations allocations leaked '
          '($liveBytes bytes)');
    for (final (index, origin) in origins.indexed) {
      buffer.writeln('  leak #${index + 1} allocated at:');
      for (final line in origin.toString().trimRight().split('\n').take(6)) {
        buffer.writeln('    $line');
      }
    }
    return buffer.toString().trimRight();
  }
}

/// An [Allocator] that accounts for every allocation passing through it.
///
/// Wrap the real allocator in tests and assert [report] is clean at end of
/// scope. Freeing an unknown pointer or freeing twice throws, so misuse surfaces
/// where it happens instead of corrupting the heap.
final class TrackingAllocator implements Allocator {
  /// Delegates to [delegate], or [calloc].
  ///
  /// Set [captureOrigins] to `false` in loops of many thousands of iterations,
  /// where a stack trace per allocation is too expensive.
  TrackingAllocator({Allocator? delegate, this.captureOrigins = true})
      : _delegate = delegate ?? calloc;

  final Allocator _delegate;

  /// Whether to record a stack trace at each allocation.
  final bool captureOrigins;

  final Map<int, _LiveAllocation> _live = {};
  int _totalAllocations = 0;

  @override
  Pointer<T> allocate<T extends NativeType>(int byteCount, {int? alignment}) {
    final pointer = _delegate.allocate<T>(byteCount, alignment: alignment);
    _totalAllocations++;
    _live[pointer.address] = _LiveAllocation(
      byteCount,
      captureOrigins ? StackTrace.current : null,
    );
    return pointer;
  }

  @override
  void free(Pointer<NativeType> pointer) {
    if (pointer.address == 0) return; // freeing nullptr is a documented no-op
    final removed = _live.remove(pointer.address);
    if (removed == null) {
      throw StateError(
        'free() called on 0x${pointer.address.toRadixString(16)}, which this '
        'allocator did not allocate or has already freed. Every handle has '
        'exactly one owner and exactly one release.',
      );
    }
    _delegate.free(pointer);
  }

  int get liveAllocations => _live.length;

  int get liveBytes =>
      _live.values.fold(0, (sum, entry) => sum + entry.byteCount);

  LeakReport get report => LeakReport(
        liveAllocations: _live.length,
        liveBytes: liveBytes,
        totalAllocations: _totalAllocations,
        origins: [
          for (final entry in _live.values)
            if (entry.origin case final origin?) origin,
        ],
      );

  /// Frees everything outstanding.
  ///
  /// For cleanup after a test has asserted on [report]. Calling it first defeats
  /// the purpose.
  void releaseAll() {
    for (final address in _live.keys.toList()) {
      _delegate.free(Pointer<Void>.fromAddress(address));
      _live.remove(address);
    }
  }
}

final class RssMeasurement {
  RssMeasurement({
    required this.growthBytes,
    required this.iterations,
    required this.beforeBytes,
    required this.afterBytes,
  });

  /// Excludes the warmup iterations.
  final int growthBytes;

  final int iterations;
  final int beforeBytes;
  final int afterBytes;

  double get bytesPerIteration => growthBytes / iterations;

  @override
  String toString() => 'RSS ${_mib(beforeBytes)} -> ${_mib(afterBytes)} '
      '(+${_mib(growthBytes)} over $iterations iterations, '
      '${bytesPerIteration.toStringAsFixed(1)} B/iteration)';

  static String _mib(int bytes) =>
      '${(bytes / (1 << 20)).toStringAsFixed(1)} MiB';
}

/// Runs [body] and reports how much resident memory it retains.
///
/// [warmup] iterations are excluded so one-off costs such as JIT compilation and
/// arena growth are not read as a leak.
///
/// Resident memory is coarse and belongs to the whole process. The Dart heap
/// moves independently, untouched pages may never fault in, and anything else
/// allocating at the same time reads as a leak. Callers must run without
/// concurrent allocators, which is why the tests using this are tagged
/// exclusive. Prefer [TrackingAllocator] where the allocation is ours to see.
RssMeasurement measureRssGrowth(
  void Function() body, {
  int iterations = 10000,
  int warmup = 500,
}) {
  RangeError.checkNotNegative(warmup, 'warmup');
  if (iterations < 1) {
    throw RangeError.value(iterations, 'iterations', 'must be at least 1');
  }

  for (var i = 0; i < warmup; i++) {
    body();
  }
  final before = ProcessInfo.currentRss;
  for (var i = 0; i < iterations; i++) {
    body();
  }
  final after = ProcessInfo.currentRss;

  return RssMeasurement(
    growthBytes: after - before,
    iterations: iterations,
    beforeBytes: before,
    afterBytes: after,
  );
}

/// [measureRssGrowth] for work that completes asynchronously.
///
/// Separate because awaiting inside the loop is the point: the memory a
/// callback frees is only freed once the event loop has run it, so a
/// synchronous loop would measure the queue rather than the leak.
Future<RssMeasurement> measureRssGrowthAsync(
  Future<void> Function() body, {
  int iterations = 500,
  int warmup = 50,
}) async {
  RangeError.checkNotNegative(warmup, 'warmup');
  if (iterations < 1) {
    throw RangeError.value(iterations, 'iterations', 'must be at least 1');
  }

  for (var i = 0; i < warmup; i++) {
    await body();
  }
  final before = ProcessInfo.currentRss;
  for (var i = 0; i < iterations; i++) {
    await body();
  }
  final after = ProcessInfo.currentRss;

  return RssMeasurement(
    growthBytes: after - before,
    iterations: iterations,
    beforeBytes: before,
    afterBytes: after,
  );
}

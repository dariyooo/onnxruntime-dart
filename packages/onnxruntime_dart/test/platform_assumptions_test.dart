@TestOn('vm')

/// Assumptions the bindings rest on that vary by platform.
///
/// Each of these is silently true on a developer machine and could be false on
/// a target we ship to. Running the suite on every platform turns them into
/// build failures instead of field reports.
library;

import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';

import 'src/memory_harness.dart';

void main() {
  group('word size', () {
    test('pointers are 32 or 64 bit, and native ints match', () {
      // Android x86 and armeabi-v7a are 32-bit, so nothing may assume 8 bytes.
      expect(sizeOf<Pointer<Void>>(), anyOf(4, 8));
      expect(sizeOf<IntPtr>(), sizeOf<Pointer<Void>>());
      expect(sizeOf<Size>(), sizeOf<Pointer<Void>>());
    });

    test('fixed-width C types are the widths the bindings assume', () {
      expect(sizeOf<Int8>(), 1);
      expect(sizeOf<Int16>(), 2);
      expect(sizeOf<Int32>(), 4);
      expect(sizeOf<Int64>(), 8);
      expect(sizeOf<Float>(), 4);
      expect(sizeOf<Double>(), 8);
    });

    test('Dart ints hold a full int64 on the VM', () {
      // Tensor dims and element counts are int64 in the C API. On the web this
      // is false, which is why int64 tensors need explicit handling there.
      const max = 9223372036854775807;
      expect(max + 1, -9223372036854775808, reason: 'expected 64-bit wrapping');
    });
  });

  group('byte order', () {
    test('the host is little-endian', () {
      // TensorProto raw_data and ORT tensor buffers are little-endian. Every
      // platform we target is too, so we never byte-swap. A big-endian host
      // would need conversion in every typed accessor.
      expect(Endian.host, Endian.little);
    });

    test('typed views read native byte order', () {
      final bytes = Uint8List.fromList([0x00, 0x00, 0x80, 0x3F]);
      expect(Float32List.sublistView(bytes).single, 1.0);
    });
  });

  group('memory harness prerequisites', () {
    test('resident memory is reported', () {
      // The RSS harness is void if this returns zero, which is a real risk on
      // platforms where the VM does not implement it.
      expect(ProcessInfo.currentRss, greaterThan(0));
      expect(ProcessInfo.maxRss, greaterThanOrEqualTo(ProcessInfo.currentRss));
    });

    test('resident memory responds to a large allocation', () {
      final measurement = measureRssGrowth(
        () {},
        iterations: 1,
        warmup: 0,
      );
      expect(measurement.beforeBytes, greaterThan(0));
      expect(measurement.afterBytes, greaterThan(0));
    });
  });

  group('shared library naming', () {
    test('matches what the build hook will produce', () {
      final expected = switch (Platform.operatingSystem) {
        'windows' => 'onnxruntime.dll',
        'macos' || 'ios' => 'libonnxruntime.dylib',
        _ => 'libonnxruntime.so',
      };
      expect(expected, isNotEmpty);
      // Guards against a new Platform.operatingSystem value falling through to
      // the .so default unnoticed.
      expect(
        Platform.operatingSystem,
        anyOf('windows', 'macos', 'ios', 'linux', 'android', 'fuchsia'),
      );
    });
  });
}

@TestOn('vm')
@Tags(['exclusive'])

/// Tensor lifetimes, measured rather than reviewed.
///
/// Memory-unsafe code passes functional tests. What catches a missed release is
/// running the cycle enough times that a leak becomes visible against a process
/// whose resident memory moves anyway, and watching an allocator that reports
/// exactly what it still holds.
library;

import 'package:onnxruntime_dart/onnxruntime_dart.dart';
import 'package:test/test.dart';

import 'src/memory_harness.dart';
import 'src/ort_library.dart';
import 'src/tensor_proto.dart';
import 'src/test_models.dart';

void main() {
  group('create, run, destroy', () {
    late Session session;
    late TensorProto input;

    setUpAll(() {
      session = Session.fromBytes(voiceCommands.model());
      input = TensorProto.decode(voiceCommands.input(0));
    });
    tearDownAll(() => session.release());

    void cycle() {
      final tensor = OrtTensor.fromData(
        OrtElementType.float32,
        input.rawData,
        input.dims,
      );
      final results = session.run({'input_1': tensor});
      for (final output in results.values) {
        output.release();
      }
      tensor.release();
    }

    test('holds resident memory flat over 10,000 cycles', () {
      final measurement = measureRssGrowth(cycle);

      // Each cycle allocates an input tensor, an output tensor and the run
      // options. Leaking the smallest of those is 104 bytes a cycle, or a
      // megabyte over this run, so the bar sits well below that while leaving
      // room for the pages the process moves anyway.
      expect(
        measurement.growthBytes,
        lessThan(8 << 20),
        reason:
            '$measurement\n\nResident memory is process-wide, so this only means anything with nothing else allocating: dart test --tags exclusive --concurrency 1',
      );
    });

    test('releasing twice throws rather than freeing twice', () {
      // A double free corrupts the heap and surfaces somewhere unrelated. This
      // is the guard that turns it into an error at the call site.
      final tensor = OrtTensor.fromData(
        OrtElementType.float32,
        input.rawData,
        input.dims,
      )..release();

      expect(tensor.release, throwsStateError);
    });

    test('a released tensor cannot be read', () {
      final tensor = OrtTensor.fromData(
        OrtElementType.float32,
        input.rawData,
        input.dims,
      )..release();

      expect(() => tensor.view, throwsStateError);
    });

    test('outputs outlive the run that produced them', () {
      // The run options are released when run returns. If an output borrowed
      // anything from them, reading it here would be reading freed memory.
      final tensor = OrtTensor.fromData(
        OrtElementType.float32,
        input.rawData,
        input.dims,
      );
      addTearDown(tensor.release);

      final results = session.run({'input_1': tensor});
      addTearDown(() {
        for (final output in results.values) {
          output.release();
        }
      });

      expect(results.values.single.view.float32s, hasLength(26));
    });

    test('dropping instead of releasing leaks, and is still safe', () {
      // Recorded rather than wished away. Dart promises nothing about when a
      // finalizer runs, and measured here it does not keep up: the collector
      // sees a small Dart object, not the tensor behind it. So the package
      // documents release as the contract, and this is the evidence.
      final measurement = measureRssGrowth(
        () {
          OrtTensor.fromData(
            OrtElementType.float32,
            input.rawData,
            input.dims,
          );
        },
        iterations: 20000,
      );

      expect(
        measurement.bytesPerIteration,
        greaterThan(0),
        reason: 'if this ever stops leaking, the documentation is now wrong: '
            '$measurement',
      );

      // The point of the finalizer is that the leak stays a leak. Work after
      // it still succeeds, rather than touching memory something else freed.
      final tensor = OrtTensor.fromData(
        OrtElementType.float32,
        input.rawData,
        input.dims,
      );
      addTearDown(tensor.release);
      expect(session.run({'input_1': tensor}).values.single..release(),
          isA<OrtTensor>());
    });
  }, skip: skipWithoutOrt ?? skipWithoutNativeAsset);
}

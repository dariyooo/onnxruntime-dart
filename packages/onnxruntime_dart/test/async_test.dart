@TestOn('vm')
@Tags(['exclusive'])

/// Running without blocking the isolate.
///
/// `RunAsync` hands the work to ONNX Runtime's own thread pool and calls back
/// on one of its threads. What is being checked is that the results are the
/// same as a synchronous run, that several runs can be in flight against one
/// session, and that nothing leaks across the callback.
library;

import 'dart:typed_data';

import 'package:onnxruntime_dart/onnxruntime_dart.dart';
import 'package:test/test.dart';

import 'src/memory_harness.dart';
import 'src/ort_library.dart';
import 'src/tensor_proto.dart';
import 'src/test_models.dart';

void main() {
  group('runAsync', () {
    late Session session;
    late TensorProto input;

    setUp(() {
      session = Session.fromBytes(voiceCommands.model());
      input = TensorProto.decode(voiceCommands.input(0));
    });
    tearDown(() => session.release());

    OrtTensor feed() => OrtTensor.fromData(
          OrtElementType.float32,
          input.rawData,
          input.dims,
        );

    test('matches a synchronous run', () async {
      final synchronous = session.run({'input_1': feed()});
      final asynchronous = await session.runAsync({'input_1': feed()});

      expect(
        asynchronous['dense_1']!.view.data,
        synchronous['dense_1']!.view.data,
      );
    });

    test('several runs can be in flight at once', () async {
      // One session, one copy of the weights, N runs. This is the reason the
      // asynchronous path exists.
      final results = await Future.wait([
        for (var i = 0; i < 8; i++) session.runAsync({'input_1': feed()}),
      ]);

      final first = results.first['dense_1']!.view.data;
      for (final result in results) {
        expect(result['dense_1']!.view.data, first);
      }
    });

    test('a bad input surfaces in the caller', () async {
      // Wrong rank, so the failure comes from the run rather than from us.
      final wrong = OrtTensor.fromData(
        OrtElementType.float32,
        Float32List(6),
        [6],
      );
      addTearDown(wrong.release);

      await expectLater(
        session.runAsync({'input_1': wrong}),
        throwsA(isA<OrtException>()),
      );
    });

    test('a missing input is rejected before the runtime sees it', () {
      expect(session.runAsync({}), throwsArgumentError);
    });

    test('holds memory flat over many runs', () async {
      // The arrays handed to RunAsync are freed in the callback, which is the
      // one place a leak here would hide. Every run allocates four arrays plus
      // one string per name, so a missed free shows up quickly.
      final measurement = await measureRssGrowthAsync(
        () async {
          final tensor = feed();
          final results = await session.runAsync({'input_1': tensor});
          results.values.single.release();
          tensor.release();
        },
        iterations: 2000,
        // Each run allocates a native callable and five arrays. Reclaiming
        // those settles a few hundred iterations in, and measuring before it
        // does reads the settling as a leak.
        warmup: 500,
      );

      // A missed free here is at least 40 bytes per run and grows without
      // bound. Resident memory moves in pages either way, so the bar is what
      // separates a leak from that noise, not zero.
      expect(
        measurement.growthBytes,
        lessThan(4 << 20),
        reason:
            '$measurement\n\nResident memory is process-wide, so this only means anything with nothing else allocating: dart test --tags exclusive --concurrency 1',
      );
    });
  }, skip: skipWithoutOrt ?? skipWithoutNativeAsset);

  group('one intra-op thread', () {
    test('is rejected with a reason', () {
      final session = Session.fromBytes(
        voiceCommands.model(),
        options: const SessionOptions(intraOpNumThreads: 1),
      );
      addTearDown(session.release);

      expect(
        () => session.runAsync({}),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('two intra-op threads'),
          ),
        ),
      );
    });
  }, skip: skipWithoutOrt ?? skipWithoutNativeAsset);
}

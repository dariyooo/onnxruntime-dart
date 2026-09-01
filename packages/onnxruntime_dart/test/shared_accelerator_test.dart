@Tags(['exclusive'])

/// Every accelerator this platform offers, actually used.
///
/// Deliberately not `@TestOn`. The rest of the suite proves the plumbing but
/// never asks for an accelerator, so every run in it is on the CPU. This is
/// the one that asks, on whichever platform it is: the WebGPU and CUDA and QNN
/// plugins on native, WebGPU and WebNN on the web. What differs is only how
/// one becomes available, which `src/accelerators.dart` answers.
///
/// The check is agreement with the CPU rather than speed. A wrong answer from
/// an accelerator is the failure worth catching, and timing a small model
/// proves nothing on any of them.
library;

import 'dart:typed_data';

import 'package:onnxruntime_dart/onnxruntime_dart.dart';
import 'package:test/test.dart';

import 'src/accelerators.dart';
import 'src/embedded_model.dart';
import 'src/runtime.dart';

/// Values with both signs, so a provider that quietly dropped the operator
/// could not agree by accident.
final _input = Float32List.fromList([-1, 2, -3, 4, -5, 6, -7, 8, -9, 10]);

const _expected = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];

/// Runs the model once and copies the output out.
///
/// `load` and `runAsync` because this has to work on the Asyncify build, where
/// the synchronous forms refuse. They are the same call on native.
Future<List<double>> _run(SessionOptions options) async {
  final session = await Session.load(absModel(), options: options);
  try {
    final input = OrtTensor.fromData(OrtElementType.float32, _input, [1, 2, 5]);
    try {
      final outputs =
          await session.runAsync({session.inputs.single.name: input});
      final output = outputs.values.single;
      try {
        return List<double>.from(output.view.float32s);
      } finally {
        output.release();
      }
    } finally {
      input.release();
    }
  } finally {
    session.release();
  }
}

SessionOptions _on(Accelerator accelerator) => SessionOptions(
      providers: [
        (name: accelerator.name, configuration: accelerator.configuration),
      ],
    );

Future<void> main() async {
  // Before the groups are declared, because on the web which accelerators
  // exist is a property of the module that gets fetched here.
  await ensureRuntime();

  for (final accelerator in accelerators()) {
    group('on ${accelerator.label}', () {
      setUpAll(() async {
        if (accelerator.skip == null) await accelerator.ensure();
      });

      test('a session can be created and run', () async {
        final answer = await _run(_on(accelerator));
        expect(answer, hasLength(10));
      });

      test('it gives the same answer as the CPU', () async {
        final onCpu = await _run(const SessionOptions());
        final accelerated = await _run(_on(accelerator));

        expect(accelerated, onCpu);
        expect(accelerated, _expected);
      });

      test('a second session works, so the device is reusable', () async {
        // Creating one, releasing it and creating another is where a provider
        // that tears down its device too eagerly falls over, and loading
        // models on demand does exactly this.
        for (var i = 0; i < 2; i++) {
          expect(await _run(_on(accelerator)), _expected);
        }
      });
    }, skip: accelerator.skip);
  }
}

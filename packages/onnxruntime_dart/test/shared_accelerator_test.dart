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

/// Options for a session this file will drive asynchronously.
///
/// The thread count is set here rather than by each caller. Every run below
/// goes through `runAsync`, which native dispatches onto the intra-op pool and
/// refuses below two threads, and the default is the machine's core count — so
/// an options object built without it decides the test by where it ran. Owning
/// it in one place is why the CPU baseline cannot be the one that forgets.
SessionOptions _options([Accelerator? accelerator]) => SessionOptions(
      providers: accelerator == null
          ? const []
          : [
              (
                name: accelerator.name,
                configuration: accelerator.configuration,
              ),
            ],
      intraOpNumThreads: asyncIntraOpThreads,
    );

Future<void> main() async {
  // Before the groups are declared, because on the web which accelerators
  // exist is a property of the module that gets fetched here.
  await ensureRuntime();

  final available = accelerators();

  // Without this the suite reports green having registered nothing at all. On
  // native, accelerators() returns an empty list when no plugin is usable, so
  // the loop below produces no groups, no tests, and no skips either, and
  // every CI guard in this repository looks for the word "skip". An audit
  // found it: the one suite that runs a model on an accelerator could vanish
  // without a trace. A test that says so is the difference between "nothing
  // ran here" and "nothing ran here and nobody noticed".
  test('some accelerator is available to test, or the reason is named', () {
    expect(
      available,
      isNotEmpty,
      reason: 'no accelerator was usable, so nothing below this line ran. On '
          'a machine with no plugin that is expected and this test is the '
          'only evidence of it. In CI it means a provider that should be '
          'staged was not, and the suite would otherwise have passed empty.',
    );
  }, skip: skipWithoutAccelerators);

  for (final accelerator in available) {
    group('on ${accelerator.label}', () {
      setUpAll(() async {
        if (accelerator.skip == null) await accelerator.ensure();
      });

      test('a session can be created and run', () async {
        final answer = await _run(_options(accelerator));
        expect(answer, hasLength(10));
      });

      test('it gives the same answer as the CPU', () async {
        final onCpu = await _run(_options());
        final accelerated = await _run(_options(accelerator));

        expect(accelerated, onCpu);
        expect(accelerated, _expected);
      });

      test('a second session works, so the device is reusable', () async {
        // Creating one, releasing it and creating another is where a provider
        // that tears down its device too eagerly falls over, and loading
        // models on demand does exactly this.
        for (var i = 0; i < 2; i++) {
          expect(await _run(_options(accelerator)), _expected);
        }
      });
    }, skip: accelerator.skip);
  }
}

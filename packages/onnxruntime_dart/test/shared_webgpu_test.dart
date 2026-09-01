@Tags(['exclusive'])

/// WebGPU, actually used, on whichever platform this is.
///
/// Deliberately not `@TestOn`. WebGPU is the one accelerator we can reach on
/// every platform we ship, so it is the one that can prove the provider path
/// end to end rather than per platform. What differs is only how it becomes
/// available, which `src/webgpu.dart` answers: a plugin library to register on
/// native, nothing at all on the web where it is linked into the build.
///
/// The check is agreement with the CPU rather than speed. A wrong answer from
/// the GPU is the failure worth catching, and timing a small model proves
/// nothing on either platform.
library;

import 'dart:typed_data';

import 'package:onnxruntime_dart/onnxruntime_dart.dart';
import 'package:test/test.dart';

import 'src/embedded_model.dart';
import 'src/runtime.dart';
import 'src/webgpu.dart';

/// Values with both signs, so a provider that quietly dropped the operator
/// could not agree by accident.
final _input = Float32List.fromList([-1, 2, -3, 4, -5, 6, -7, 8, -9, 10]);

/// Runs the model once and copies the output out.
///
/// `load` and `runAsync` because this has to work on the Asyncify build, where
/// the synchronous forms refuse. They are the same call on native.
Future<List<double>> _run(SessionOptions options) async {
  final session = await Session.load(absModel(), options: options);
  try {
    final input = OrtTensor.fromData(
      OrtElementType.float32,
      _input,
      [1, 2, 5],
    );
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

void main() {
  late String skip;

  setUpAll(() async {
    await ensureRuntime();
    skip = skipWithoutWebGpu ?? '';
    if (skip.isEmpty) await ensureWebGpu();
  });

  test('a session can be created on WebGPU and run', () async {
    if (skip.isNotEmpty) return markTestSkipped(skip);

    final onGpu = await _run(
      SessionOptions(
        providers: [(name: webGpuProviderName, configuration: const {})],
      ),
    );

    expect(onGpu, hasLength(10));
  });

  test('WebGPU gives the same answer as the CPU', () async {
    if (skip.isNotEmpty) return markTestSkipped(skip);

    final onCpu = await _run(const SessionOptions());
    final onGpu = await _run(
      SessionOptions(
        providers: [(name: webGpuProviderName, configuration: const {})],
      ),
    );

    expect(onGpu, onCpu);
    expect(onGpu, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
  });

  test('a second session on WebGPU works, so the device is reusable', () async {
    if (skip.isNotEmpty) return markTestSkipped(skip);

    // Creating one, releasing it and creating another is where a provider that
    // tears down its device too eagerly falls over, and an application that
    // loads models on demand does exactly this.
    for (var i = 0; i < 2; i++) {
      final answer = await _run(
        SessionOptions(
          providers: [(name: webGpuProviderName, configuration: const {})],
        ),
      );
      expect(answer, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
    }
  });
}

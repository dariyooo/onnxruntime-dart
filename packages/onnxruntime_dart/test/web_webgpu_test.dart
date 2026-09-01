@TestOn('browser')
@Tags(['exclusive'])

/// WebGPU, actually used.
///
/// The rest of the browser suite proves the Asyncify plumbing works, but it
/// never asks for an accelerator, so every run in it is on the CPU. This is
/// the one that requests WebGPU, which is also the only reason that build has
/// to create a session asynchronously: requesting a device is a promise.
///
/// The check is agreement rather than speed. A wrong answer from the GPU is
/// the failure worth catching, and timing a tiny model in a browser measures
/// nothing.
library;

import 'dart:typed_data';

import 'package:onnxruntime_dart/onnxruntime_dart.dart';
import 'package:test/test.dart';

import 'src/embedded_model.dart';
import 'src/runtime.dart';

/// Values with both signs, so a provider that dropped the operator entirely
/// would not accidentally agree.
final _input = Float32List.fromList(
  [-1, 2, -3, 4, -5, 6, -7, 8, -9, 10],
);

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
    // The Asyncify build is the WebGPU one: it is compiled that way because
    // requesting a device suspends. `availableProviders` is not the gate,
    // because the WebAssembly build reports the providers linked into it and
    // the web EPs are selected by name instead.
    skip = skipWithoutRuntime ??
        (supportsSynchronousCalls
            ? 'this is the plain WebAssembly build, which has no WebGPU'
            : '');
  });

  test('the build is the one compiled for an accelerator', () {
    if (skip.isNotEmpty) return markTestSkipped(skip);
    // Linked providers, which is a different list from the web EPs.
    expect(availableProviders(), contains('CPUExecutionProvider'));
    expect(supportsSynchronousCalls, isFalse);
  });

  test('a session can be created on webgpu and run', () async {
    if (skip.isNotEmpty) return markTestSkipped(skip);

    final onGpu = await _run(
      const SessionOptions(providers: [(name: 'WebGPU', configuration: {})]),
    );

    expect(onGpu, hasLength(10));
  });

  test('webgpu gives the same answer as the cpu', () async {
    if (skip.isNotEmpty) return markTestSkipped(skip);

    final onCpu = await _run(const SessionOptions());
    final onGpu = await _run(
      const SessionOptions(providers: [(name: 'WebGPU', configuration: {})]),
    );

    expect(onGpu, onCpu);
    expect(onGpu, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
  });
}

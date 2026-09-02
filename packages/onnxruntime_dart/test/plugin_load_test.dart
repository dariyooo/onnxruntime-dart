@TestOn('vm')
@Tags(['exclusive'])

/// Every provider plugin we ship opens.
///
/// Running a model on one needs the hardware. CI has none of it: no NVIDIA
/// card, no Qualcomm NPU, and a GPU only through software rendering. Opening a
/// plugin needs none of that, and it is the part that actually breaks, because
/// a plugin is built separately from the runtime and against a version of it
/// that has to match. `shared_accelerator_test.dart` runs models on whichever
/// of these the machine can, which in CI is usually only WebGPU.
library;

import 'package:onnxruntime_dart/src/ffi/environment.dart';
import 'package:onnxruntime_dart/src/ffi/execution_provider.dart';
import 'package:test/test.dart';

import 'src/accelerators.dart';
import 'src/ort_library.dart';

void main() {
  for (final provider in ['webgpu', 'cuda', 'qnn']) {
    group('the $provider plugin', () {
      late final OrtEnvironment env;
      setUpAll(() => env = OrtEnvironment.instance());

      test('opens, and its factory runs', () {
        final before = executionProviderDeviceCount(env.api, env.handle);

        // Registration succeeding proves the library loaded and exported
        // CreateEpFactories. Its devices appearing proves the factory ran and
        // found hardware, which is the part CI cannot promise.
        registerExecutionProviderLibrary(
          env.api,
          env.handle,
          name: 'load-$provider',
          path: pluginPath(provider)!,
        );
        addTearDown(
          () => unregisterExecutionProviderLibrary(
            env.api,
            env.handle,
            name: 'load-$provider',
          ),
        );

        final after = executionProviderDeviceCount(env.api, env.handle);
        expect(after, greaterThanOrEqualTo(before));
        printOnFailure('$provider contributed ${after - before} device(s)');
      });
    },
        skip: skipWithoutOrt ??
            skipWithoutNativeAsset ??
            (pluginPath(provider) == null
                ? 'no $provider plugin supplied'
                : null));
  }
}

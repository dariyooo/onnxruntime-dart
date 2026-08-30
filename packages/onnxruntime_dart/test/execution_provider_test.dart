@TestOn('vm')
@Tags(['exclusive'])

/// Execution provider plugins are shared libraries ONNX Runtime opens itself.
/// These cover the registration path and its failure modes. Loading a real
/// plugin needs one built, which the runtime release does not include.
library;

import 'package:onnxruntime_dart/src/ffi/environment.dart';
import 'package:onnxruntime_dart/src/ffi/execution_provider.dart';
import 'package:onnxruntime_dart/src/ffi/status.dart';
import 'package:test/test.dart';

import 'src/ort_library.dart';

void main() {
  group('environment', () {
    test('is the same instance every time', () {
      // CreateEnv returns a process-wide singleton, so wrapping it twice must
      // not produce two owners of one handle.
      expect(
        identical(OrtEnvironment.instance(), OrtEnvironment.instance()),
        isTrue,
      );
    });

    test('exposes a usable api', () {
      expect(OrtEnvironment.instance().handle.address, isNot(0));
    });
  }, skip: skipWithoutNativeAsset);

  group('execution provider plugins', () {
    late final OrtEnvironment env;
    setUpAll(() => env = OrtEnvironment.instance());

    test('a missing library is reported, not ignored', () {
      expect(
        () => registerExecutionProviderLibrary(
          env.api,
          env.handle,
          name: 'absent',
          path: '/nonexistent/libonnxruntime_providers_webgpu.so',
        ),
        throwsA(isA<OrtException>()),
      );
    });

    test('a library that is not a plugin is rejected', () {
      // The core library exports no CreateEpFactories, so registering it must
      // fail rather than half-succeed.
      expect(
        () => registerExecutionProviderLibrary(
          env.api,
          env.handle,
          name: 'not-a-plugin',
          path: 'pubspec.yaml',
        ),
        throwsA(isA<OrtException>()),
      );
    });

    test('unregistering something never registered is reported', () {
      expect(
        () => unregisterExecutionProviderLibrary(
          env.api,
          env.handle,
          name: 'never-registered',
        ),
        throwsA(isA<OrtException>()),
      );
    });

    test('device enumeration works before any plugin is registered', () {
      // The baseline a later registration is measured against.
      expect(executionProviderDeviceCount(env.api, env.handle),
          greaterThanOrEqualTo(1));
    });
  }, skip: skipWithoutNativeAsset);

  group('the WebGPU plugin we build', () {
    late final OrtEnvironment env;
    setUpAll(() => env = OrtEnvironment.instance());

    test('registers and adds its devices', () {
      final before = executionProviderDeviceCount(env.api, env.handle);

      registerExecutionProviderLibrary(
        env.api,
        env.handle,
        name: 'webgpu',
        path: findWebGpuPlugin()!,
      );
      addTearDown(
        () => unregisterExecutionProviderLibrary(
          env.api,
          env.handle,
          name: 'webgpu',
        ),
      );

      // Registration succeeding proves the library loaded and exported
      // CreateEpFactories. Its devices appearing proves the factory ran.
      expect(
        executionProviderDeviceCount(env.api, env.handle),
        greaterThan(before),
      );
    });

    test('registering the same name twice is refused', () {
      registerExecutionProviderLibrary(
        env.api,
        env.handle,
        name: 'webgpu-dup',
        path: findWebGpuPlugin()!,
      );
      addTearDown(
        () => unregisterExecutionProviderLibrary(
          env.api,
          env.handle,
          name: 'webgpu-dup',
        ),
      );

      expect(
        () => registerExecutionProviderLibrary(
          env.api,
          env.handle,
          name: 'webgpu-dup',
          path: findWebGpuPlugin()!,
        ),
        throwsA(isA<OrtException>()),
      );
    });
  }, skip: skipWithoutWebGpuPlugin ?? skipWithoutNativeAsset);
}

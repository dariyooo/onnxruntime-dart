/// The webgpu execution provider.
///
/// This package installs a library and tells ONNX Runtime where it is. The
/// asset id below has to be a compile-time constant, which is why the lookup
/// lives here rather than in onnxruntime_dart: only this package can name its
/// own asset.
library;

import 'dart:ffi';

import 'package:onnxruntime_dart/native.dart';

/// The library's file name without prefix or extension.
const providerLibraryStem = 'onnxruntime_providers_webgpu';

/// The oldest ONNX Runtime this provider works against.
const minimumRuntime = '1.24.4';

@Native<Void Function()>(
  symbol: 'CreateEpFactories',
  assetId: 'package:onnxruntime_ep_webgpu/provider',
)
external void _entryPoint();

/// Where this provider was installed, or null if it was not.
String? providerPath() => loadedLibraryPath(
      () =>
          Native.addressOf<NativeFunction<Void Function()>>(_entryPoint).cast(),
      stem: providerLibraryStem,
    );

/// Registers the provider under , and reports whether it was there.
///
/// Call before creating any session: registration mutates process-global
/// state, and racing it against session creation crashes the runtime.
bool registerWebGpu() {
  final path = providerPath();
  if (path == null) return false;

  final environment = OrtEnvironment.instance();
  registerExecutionProviderLibrary(
    environment.api,
    environment.handle,
    name: 'webgpu',
    path: path,
  );
  return true;
}

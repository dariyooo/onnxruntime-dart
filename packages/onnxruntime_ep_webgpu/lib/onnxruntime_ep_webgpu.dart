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
/// Register before creating a session that should use it. There is no need to
/// do it first: ONNX Runtime places no ordering constraint on registration, so
/// a provider downloaded at run time can be registered then and used by every
/// session created afterwards. Sessions already built keep the providers they
/// were built with.
///
/// It does mutate the environment, so do not race it against session creation
/// on another isolate.
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

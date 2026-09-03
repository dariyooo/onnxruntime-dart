/// The cuda execution provider.
///
/// This package installs a library and tells ONNX Runtime where it is. The
/// asset id below has to be a compile-time constant, which is why the lookup
/// lives here rather than in onnxruntime_dart: only this package can name its
/// own asset.
library;

import 'dart:ffi';

import 'package:onnxruntime_dart/native.dart';

/// The library's file name without prefix or extension.
const providerLibraryStem = 'onnxruntime_providers_cuda';

/// The oldest ONNX Runtime this provider works against.
const minimumRuntime = '1.24.4';

@Native<Void Function()>(
  symbol: 'CreateEpFactories',
  assetId: 'package:onnxruntime_ep_cuda_binaries/provider',
)
external void _entryPoint();

/// Where this provider was installed, or null if it was not.
String? providerPath() => loadedLibraryPath(
      () =>
          Native.addressOf<NativeFunction<Void Function()>>(_entryPoint).cast(),
      stem: providerLibraryStem,
    );

/// Registers the provider under `cuda`, and reports whether it was there.
///
/// Register before creating a session that should use it. There is no need to
/// do it first: ONNX Runtime places no ordering constraint on registration, so
/// a provider downloaded at run time can be registered then and used by every
/// session created afterwards. Sessions already built keep the providers they
/// were built with.
///
/// It does mutate the environment, so do not race it against session creation
/// on another isolate.
///
/// Calling twice is a no-op. Registration is process-wide, so a second call
/// would otherwise fail with "already registered" for the unhelpful reason
/// that the first one worked.
bool registerCuda() {
  final path = providerPath();
  if (path == null) return false;
  if (_registered) return true;

  final environment = OrtEnvironment.instance();
  try {
    registerExecutionProviderLibrary(
      environment.api,
      environment.handle,
      name: 'cuda',
      path: path,
    );
  } on OrtException catch (error) {
    // Registration is process-wide but this flag is not, so another isolate
    // may have done it already. That is the outcome asked for either way.
    if (!error.message.contains('already registered')) rethrow;
  }

  _registered = true;
  return true;
}

/// Whether this isolate has already registered the provider.
var _registered = false;

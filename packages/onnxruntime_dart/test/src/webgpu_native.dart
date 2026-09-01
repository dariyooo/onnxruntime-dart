/// Making WebGPU usable on a native platform.
///
/// It arrives as a plugin library that ships in its own package, so it has to
/// be registered before a session can name it.
library;

import 'package:onnxruntime_dart/onnxruntime_dart.dart';

import 'ort_library.dart';

/// What a session calls the provider once it is available.
const webGpuProviderName = 'webgpu';

/// Reason to skip, or null when WebGPU can be used here.
String? get skipWithoutWebGpu => skipWithoutOrt ?? skipWithoutWebGpuPlugin;

var _registered = false;

/// Registers the plugin. Safe to call more than once.
Future<void> ensureWebGpu() async {
  if (_registered || skipWithoutWebGpu != null) return;
  registerProviderLibrary(
    name: webGpuProviderName,
    path: findWebGpuPlugin()!,
  );
  _registered = true;
}

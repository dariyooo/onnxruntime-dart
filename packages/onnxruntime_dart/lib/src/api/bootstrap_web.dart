/// Preparing the runtime on the web, where the module has to be fetched.
///
/// The one place the platforms genuinely differ. Everything after this call is
/// the same code as native runs.
library;

import '../backend/calls.dart';
import '../backend/wasm/loader.dart';
import 'options.dart';

export 'options.dart';

/// Fetches and instantiates the WebAssembly runtime.
///
/// [native] is accepted and ignored, so one call site works on every platform.
/// Calling twice is a no-op: the runtime keeps process-global state and two
/// instances would be two of everything.
Future<void> openOnnxRuntime({
  WebRuntimeOptions? web,
  NativeRuntimeOptions? native,
}) async {
  if (web == null) {
    // Naming which packages publish the URLs, because that is the next
    // question and it is nobody's job to guess.
    throw ArgumentError.value(
      null,
      'web',
      'openOnnxRuntime needs WebRuntimeOptions on the web: the WebAssembly '
          'runtime is fetched at startup rather than linked in. The URLs come '
          'from onnxruntime_web, onnxruntime_web_webgpu or '
          'onnxruntime_web_webgpu_webnn:\n'
          '\n'
          '  await openOnnxRuntime(web: WebRuntimeOptions(ortLoaderUrl));',
    );
  }

  await loadOrtWasm(
    loaderUrl: web.loader,
    wasmUrl: web.wasm,
    wasmBytes: web.wasmBytes,
    threads: web.threads,
  );
  createCalls().init();
}

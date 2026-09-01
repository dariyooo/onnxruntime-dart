/// Preparing the runtime on the web, where the module has to be fetched.
///
/// The one place the platforms genuinely differ. Everything after this call is
/// the same code as native runs.
library;

import '../backend/calls.dart';
import '../backend/wasm/asyncify.dart';
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

/// Whether this runtime accepts the synchronous calls.
///
/// True everywhere except a WebGPU or WebNN build of the web runtime. Those
/// are compiled with Asyncify, where creating a session or running one can
/// suspend, and a synchronous call has no way to wait for it. The synchronous
/// forms refuse there rather than hand back a promise as though it were a
/// result.
///
/// Code that has to run on every build should use [Session.load] and
/// `runAsync`, which work the same on all of them. This is here for code that
/// wants to take the synchronous path where it exists and can fall back.
///
/// Only meaningful after `openOnnxRuntime`, which is what decides the answer
/// on the web.
bool get supportsSynchronousCalls => !isAsyncifyBuild(ortModule);

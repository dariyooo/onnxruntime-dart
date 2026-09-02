/// Loading ONNX Runtime's WebAssembly build.
///
/// The build is two files: an Emscripten loader (`.mjs`) that default-exports
/// a factory, and the `.wasm` it fetches. Instantiating is asynchronous and
/// the backend seam is not, so an application loads the runtime once before
/// using it and everything after that is synchronous.
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import '../../version.g.dart';
import 'module.dart';

/// The module, once loaded. Null until [loadOrtWasm] has completed.
OrtModule? _module;

/// Threads the loaded module was started with. See [usableThreads].
int _threads = 1;

/// How many threads the runtime is running with.
///
/// Fixed when the module is instantiated, because the worker pool is created
/// then, so the backend reports rather than chooses.
int get ortWasmThreads => _threads;

/// A thread count this page can actually use.
///
/// The workers need `SharedArrayBuffer`, which is only available when the page
/// is served cross-origin isolated. Asking for more than one without it does
/// not degrade, it fails to start the runtime, so the safe answer is one.
int usableThreads(int? requested) {
  final isolated =
      (globalContext['crossOriginIsolated'] as JSBoolean?)?.toDart ?? false;
  if (!isolated) return 1;

  final cores = (globalContext['navigator'] as JSObject?)
          ?.getProperty<JSNumber?>('hardwareConcurrency'.toJS)
          ?.toDartInt ??
      1;
  // More workers than cores costs scheduling and wins nothing.
  return requested ?? (cores < 1 ? 1 : cores);
}

/// The loaded module, or an error naming what to call first.
OrtModule get ortModule {
  final module = _module;
  if (module == null) {
    throw StateError(
      'ONNX Runtime has not been loaded. Await loadOrtWasm() before using the '
      'runtime on the web: the WebAssembly module has to be fetched and '
      'instantiated, which cannot happen synchronously.',
    );
  }
  return module;
}

bool get ortWasmIsLoaded => _module != null;

/// The ONNX Runtime version the loaded build carries.
///
/// The WebAssembly build exports no version string, so this comes from the
/// pinned submodule instead. The asset packages are built from that same
/// submodule in the same run, so the two cannot disagree.
const wasmRuntimeVersion = ortVersion;

/// Fetches and instantiates the runtime.
///
/// [loaderUrl] is the `.mjs`. [wasmBytes] is the `.wasm` when the caller has
/// it already, which is the reliable path: the loader otherwise resolves the
/// `.wasm` relative to itself, and that is exactly what a bundler moves.
///
/// Calling twice is a no-op, because the runtime keeps process-global state
/// and instantiating it twice would produce two of everything.
Future<void> loadOrtWasm({
  required String loaderUrl,
  Uint8List? wasmBytes,
  String? wasmUrl,
  int? threads,
}) async {
  if (_module != null) return;
  _refuseJspi(loaderUrl);

  final JSObject namespace;
  try {
    // importModule is the SDK's dynamic import: `import` itself is a
    // keyword rather than a callable global, so it cannot be bound.
    namespace = await importModule(loaderUrl.toJS).toDart;
  } on Object catch (error) {
    throw StateError('could not load $loaderUrl: $error');
  }

  final factory = namespace.getProperty<JSFunction?>('default'.toJS);
  if (factory == null) {
    throw StateError(
      '$loaderUrl has no default export, so it is not an Emscripten module '
      'built with MODULARIZE=1',
    );
  }

  // A plain object, not an extension type: there is no JS class to construct,
  // only a bag of properties the factory reads. The build pins
  // INCOMING_MODULE_JS_API to [locateFile, instantiateWasm, wasmBinary], so
  // anything else here would be ignored.
  final options = JSObject();

  // Read at startup to size the worker pool: PTHREAD_POOL_SIZE is
  // Module["numThreads"] - 1, so this has to be set before instantiating.
  _threads = usableThreads(threads);
  options.setProperty('numThreads'.toJS, _threads.toJS);

  if (wasmBytes != null) {
    options.setProperty('wasmBinary'.toJS, wasmBytes.toJS);
  } else if (wasmUrl != null) {
    options.setProperty(
      'locateFile'.toJS,
      ((JSString _, JSString __) => wasmUrl.toJS).toJS,
    );
  }

  final resolved =
      await (factory.callAsFunction(null, options)! as JSPromise<JSObject>)
          .toDart;
  _module = OrtModule(resolved);
}

/// Forgets the loaded module. For tests that need a fresh one.
void resetOrtWasmForTesting() => _module = null;

/// Refuses a JSPI build, which this package cannot drive.
///
/// ONNX Runtime can be built with JSPI instead of Asyncify, and upstream is
/// moving that way: smaller, faster, and quicker to link. The two are not
/// interchangeable here. A JSPI build defines no `asyncInit`, so the backend
/// would be chosen as the synchronous one, and the five exports that suspend
/// would hand back promises to be read as integers. Nothing would throw; the
/// results would simply be wrong.
///
/// Detected by name, because upstream distinguishes the builds only by
/// filename and the module carries no marker. A heuristic, but the failure it
/// prevents is silent, and refusing a build we cannot drive is better than
/// running it wrongly.
void _refuseJspi(String loaderUrl) {
  if (!loaderUrl.contains('.jspi.')) return;

  throw UnsupportedError(
    'this looks like a JSPI build of ONNX Runtime ($loaderUrl), which this '
    'package cannot drive. It suspends through JavaScript Promise '
    'Integration rather than Asyncify, and the two are told apart only by '
    'file name, so a JSPI build would be taken for a synchronous one and its '
    'results read as though a promise were a number. Serve the Asyncify build '
    'instead: the same directory publishes ort-wasm-simd-threaded.asyncify.mjs '
    'beside the .jspi one.',
  );
}

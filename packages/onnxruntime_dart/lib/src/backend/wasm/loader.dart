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

@JS('import')
external JSPromise<JSObject> _import(JSString url);

/// Options handed to the Emscripten factory.
///
/// Only what the build accepts: `INCOMING_MODULE_JS_API` is pinned to
/// `[locateFile,instantiateWasm,wasmBinary]`, and anything else is ignored.
extension type _Options._(JSObject _) implements JSObject {
  external factory _Options();
  external set wasmBinary(JSUint8Array value);
  external set locateFile(JSFunction value);
}

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
}) async {
  if (_module != null) return;

  final JSObject namespace;
  try {
    namespace = await _import(loaderUrl.toJS).toDart;
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

  final options = _Options();
  if (wasmBytes != null) {
    options.wasmBinary = wasmBytes.toJS;
  } else if (wasmUrl != null) {
    options.locateFile = ((JSString _, JSString __) => wasmUrl.toJS).toJS;
  }

  final resolved =
      await (factory.callAsFunction(null, options)! as JSPromise<JSObject>)
          .toDart;
  _module = OrtModule(resolved);
}

/// Forgets the loaded module. For tests that need a fresh one.
void resetOrtWasmForTesting() => _module = null;

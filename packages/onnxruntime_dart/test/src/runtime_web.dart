/// Runtime availability on the web.
///
/// The WebAssembly build has to be fetched, so a browser run needs to be told
/// where it is. `web_runtime_config.dart` holds that and is empty until
/// something puts the runtime there, so a fresh checkout skips these rather
/// than failing.
///
/// The loader is imported from its own URL, because Emscripten derives its
/// script directory from `import.meta.url` and a blob has no usable base. The
/// `.wasm` is fetched and passed as bytes instead of a URL, so nothing has to
/// resolve a second path relative to wherever the test page happens to live.
library;

import 'dart:js_interop';
import 'dart:typed_data';

import 'package:onnxruntime_dart/onnxruntime_dart.dart';
import 'package:web/web.dart' as web;

import 'web_runtime_config.dart';

/// Reason to skip, or null when the runtime can be used here.
String? get skipWithoutRuntime => webRuntimeLoader.isEmpty
    ? 'no WebAssembly runtime here; run tool/fetch_web_runtime.sh first'
    : null;

var _loaded = false;

/// Fetches and instantiates the runtime. Safe to call more than once.
Future<void> ensureRuntime() async {
  if (webRuntimeLoader.isEmpty || _loaded) return;

  final wasm = await _bytes(webRuntimeWasm);
  await openOnnxRuntime(
    web: WebRuntimeOptions(loader: webRuntimeLoader, wasmBytes: wasm),
  );
  _loaded = true;
}

Future<Uint8List> _bytes(String url) async {
  final response = await web.window.fetch(url.toJS).toDart;
  if (!response.ok) {
    throw StateError('could not fetch $url: HTTP ${response.status}');
  }
  return (await response.arrayBuffer().toDart).toDart.asUint8List();
}

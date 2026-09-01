/// Per-platform options for [openOnnxRuntime].
///
/// Both are accepted everywhere and the one that does not apply is ignored, so
/// a single call site compiles and runs on every platform. The alternative is
/// an application writing two call sites behind a conditional import, which is
/// exactly the thing this is meant to remove.
library;

import 'dart:typed_data';

/// Where to find the WebAssembly runtime. Ignored off the web.
///
/// The asset packages publish both URLs, so the usual call is:
///
/// ```dart
/// import 'package:onnxruntime_web/onnxruntime_web.dart' as assets;
///
/// await openOnnxRuntime(
///   web: WebRuntimeOptions(loader: assets.ortLoaderUrl, wasm: assets.ortWasmUrl),
/// );
/// ```
final class WebRuntimeOptions {
  const WebRuntimeOptions({required this.loader, this.wasm, this.wasmBytes});

  /// The Emscripten loader, which is the `.mjs`.
  final String loader;

  /// The `.wasm` the loader fetches. Leave null to let it resolve one beside
  /// the loader, which works until a bundler moves them apart.
  final String? wasm;

  /// The `.wasm` already in memory, which is the reliable option: nothing has
  /// to resolve a URL at all.
  final Uint8List? wasmBytes;
}

/// How many threads the runtime may use, and how loudly it logs. Ignored on
/// the web, where both are fixed when the module is instantiated.
final class NativeRuntimeOptions {
  const NativeRuntimeOptions({this.logLevel = 2});

  /// An `OrtLoggingLevel`. Two is warning.
  final int logLevel;
}

/// The ONNX Runtime WebAssembly runtime, bundled for Flutter web.
///
/// This one is XNNPACK and WebGPU.
///
/// A browser cannot open a shared library, so on the web the accelerators are
/// compiled into the `.wasm` and the choice is made by which package you
/// depend on. Serving the files yourself still works and needs none of this.
library;

export 'src/asset.dart' show ortLoaderUrl, ortWasmUrl, ortWebBuild;

/// Where Flutter serves this build from.
///
/// Package assets are served under `assets/packages/<package>/`, which is
/// stable and needs no configuration. Both files are needed: the `.mjs` is the
/// loader, and it fetches the `.wasm` beside it.
library;

/// The loader to hand to ONNX Runtime's WebAssembly entry point.
const ortLoaderUrl =
    'assets/packages/onnxruntime_web_webgpu/assets/ort-wasm-simd-threaded.asyncify.mjs';

/// The runtime itself, fetched by the loader.
const ortWasmUrl =
    'assets/packages/onnxruntime_web_webgpu/assets/ort-wasm-simd-threaded.asyncify.wasm';

/// Which build this package carries, as named by the build matrix.
const ortWebBuild = 'web-wasm-webgpu';

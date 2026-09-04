/// Selects the backend for the platform being compiled for.
///
/// Resolved at compile time, so a web build never references `dart:ffi`. The
/// same arrangement as the base package, and for the same reason: one
/// `dart:ffi` import above this line breaks the package in a consumer's web
/// build rather than in ours.
///
/// Upstream publishes no WebAssembly build of GenAI, so the web side answers
/// every call with `GenAiUnsupported` rather than doing the work. That is not
/// the same as the package being unusable there: it compiles, which is what an
/// application that uses GenAI on native and something else on the web needs.
///
/// Building one ourselves was considered and declined. The pieces are closer
/// to hand than they look: this repository already builds ONNX Runtime to
/// wasm, and GenAI can take a model from memory through `OgaConfigAddModelData`
/// rather than from a filesystem. What is missing is emscripten support in
/// GenAI's own CMake, which upstream has none of and does not test. Adding it
/// would mean carrying a fork of their build, and that cost is ongoing while
/// the benefit is one platform.
///
/// So the decision is to wait for upstream. If they add it, the work here is
/// one file: a `wasm_calls.dart` implementing the same interface, named in the
/// export below in place of `unsupported_calls.dart`. Nothing above the
/// boundary changes, which is the reason the boundary is here.
library;

export 'ffi_calls.dart' if (dart.library.js_interop) 'unsupported_calls.dart'
    show createCalls;

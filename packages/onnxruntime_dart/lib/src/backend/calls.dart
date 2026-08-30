/// Selects the backend for the platform being compiled for.
///
/// Resolved at compile time, so a web build never references `dart:ffi` and a
/// native build never references `dart:js_interop`.
library;

export 'ffi_calls.dart' if (dart.library.js_interop) 'wasm_calls.dart'
    show createCalls;

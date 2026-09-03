/// Selects the backend for the platform being compiled for.
///
/// Resolved at compile time, so a web build never references `dart:ffi`. The
/// same arrangement as the base package, and for the same reason: one
/// `dart:ffi` import above this line breaks the package in a consumer's web
/// build rather than in ours.
///
/// Upstream publishes no WebAssembly build of GenAI, so the web side answers
/// every call with [GenAiUnsupported] rather than doing the work. That is not
/// the same as the package being unusable there: it compiles, which is what an
/// application that uses GenAI on native and something else on the web needs.
library;

export 'ffi_calls.dart' if (dart.library.js_interop) 'unsupported_calls.dart'
    show createCalls;

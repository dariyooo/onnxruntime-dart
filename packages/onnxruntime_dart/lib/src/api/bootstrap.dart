/// Preparing the runtime, on whichever platform this is.
///
/// The only thing an application has to do differently. Native bundles the
/// library as a code asset and the loader has it before `main` runs; the web
/// has to fetch and instantiate a WebAssembly module, which cannot happen
/// synchronously.
///
/// So there is one call, it returns a future on both, and it completes
/// immediately on native. Everything after it is identical.
library;

export 'bootstrap_native.dart'
    if (dart.library.js_interop) 'bootstrap_web.dart';

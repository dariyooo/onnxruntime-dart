/// The accelerators this platform can actually be asked to run a model on.
///
/// One list, filled differently per platform, so the tests over it are shared.
/// What differs is only how an accelerator becomes available: a plugin library
/// to register on native, and on the web nothing at all, since the provider is
/// compiled into the build being served and the browser decides the rest.
library;

export 'accelerators_native.dart'
    if (dart.library.js_interop) 'accelerators_web.dart';

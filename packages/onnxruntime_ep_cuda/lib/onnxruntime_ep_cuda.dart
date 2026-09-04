/// The cuda execution provider.
///
/// One API on both platforms. Native installs a library and registers it with
/// the runtime; a web build has no such library, so the question becomes
/// whether the runtime being served already carries the provider. Both answer
/// [registerCuda], so an application asks once and does not branch on which
/// platform it is running on.
///
/// The split is a conditional export, resolved at compile time, so a web build
/// never references `dart:ffi`. Importing this package used to break a web
/// build outright, which made it unusable to anyone shipping both.
library;

export 'src/identity.dart' show minimumRuntime, providerLibraryStem;
export 'src/register_ffi.dart'
    if (dart.library.js_interop) 'src/register_web.dart'
    show providerPath, registerCuda;

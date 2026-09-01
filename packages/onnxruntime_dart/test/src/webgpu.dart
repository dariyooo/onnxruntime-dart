/// WebGPU availability, on whichever platform this is.
///
/// The same session code names the provider on both. What differs is only how
/// it becomes available: a plugin library to register on native, and nothing
/// at all on the web, where it is compiled into the build being served.
library;

export 'webgpu_native.dart' if (dart.library.js_interop) 'webgpu_web.dart';

/// Whether a runtime is usable here, and getting it ready.
///
/// The same tests should run wherever ONNX Runtime can run. What differs is
/// only how it arrives: native has it as a code asset before `main`, the web
/// has to fetch it. Both are behind this, so a test says `skip:
/// skipWithoutRuntime` and does not care which platform it is on.
library;

export 'runtime_native.dart' if (dart.library.js_interop) 'runtime_web.dart';

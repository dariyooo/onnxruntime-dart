/// Preparing the runtime on a native platform, where there is nothing to do.
///
/// The library is a code asset, so the loader has already mapped it. This
/// exists so an application can call the same function everywhere rather than
/// writing a conditional import of its own.
library;

import '../backend/calls.dart';
import 'options.dart';

export 'options.dart';

/// Readies the runtime. Completes immediately here.
///
/// [web] is accepted and ignored, so one call site works on every platform.
Future<void> openOnnxRuntime({
  WebRuntimeOptions? web,
  NativeRuntimeOptions? native,
}) async {
  createCalls().init(loggingLevel: native?.logLevel ?? 2);
}

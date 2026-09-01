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

/// Whether this runtime accepts the synchronous calls.
///
/// True everywhere except a WebGPU or WebNN build of the web runtime. Those
/// are compiled with Asyncify, where creating a session or running one can
/// suspend, and a synchronous call has no way to wait for it. The synchronous
/// forms refuse there rather than hand back a promise as though it were a
/// result.
///
/// Code that has to run on every build should use [Session.load] and
/// `runAsync`, which work the same on all of them. This is here for code that
/// wants to take the synchronous path where it exists and can fall back.
///
/// Only meaningful after `openOnnxRuntime`, which is what decides the answer
/// on the web.
bool get supportsSynchronousCalls => true;

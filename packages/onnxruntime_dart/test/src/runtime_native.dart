/// Runtime availability on a native platform.
library;

import 'package:onnxruntime_dart/onnxruntime_dart.dart';

import 'ort_library.dart';

/// Reason to skip, or null when the runtime can be used here.
String? get skipWithoutRuntime => skipWithoutOrt ?? skipWithoutNativeAsset;

/// Readies the runtime. Nothing to do: it is a code asset already mapped.
Future<void> ensureRuntime() async {}

/// Options a session needs to be run asynchronously here.
///
/// ONNX Runtime hands an asynchronous run to its own intra-op pool and refuses
/// below two threads. The default is whatever the machine offers, which is
/// enough on a developer's laptop and not on every CI runner, so leaving it
/// unset would make the same test pass or fail by where it ran.
const asyncSessionOptions = SessionOptions(intraOpNumThreads: 2);

/// Intra-op threads an asynchronous run needs here, for callers that build
/// their own options and cannot use [asyncSessionOptions] wholesale.
const asyncIntraOpThreads = 2;

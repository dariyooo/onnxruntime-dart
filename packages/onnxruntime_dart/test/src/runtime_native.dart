/// Runtime availability on a native platform.
library;

import 'ort_library.dart';

/// Reason to skip, or null when the runtime can be used here.
String? get skipWithoutRuntime => skipWithoutOrt ?? skipWithoutNativeAsset;

/// Readies the runtime. Nothing to do: it is a code asset already mapped.
Future<void> ensureRuntime() async {}

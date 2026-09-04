/// The provider on the web, where it is compiled in rather than loaded.
///
/// Nothing is registered here, and that is not a limitation being worked
/// around. The WebAssembly builds compile their accelerators in, so a provider
/// is either already present or was never built, and there is no third state
/// that registering could reach.
///
/// So the question this half answers is not "did registering work" but "is it
/// here", which is the same question the native half answers by a different
/// route. That is what lets an application call it on both platforms without
/// asking which one it is on.
library;

import 'package:onnxruntime_dart/onnxruntime_dart.dart';

import 'identity.dart';

/// Null, always: nothing was installed as a file.
///
/// The runtime is fetched as an asset and the provider is inside it, so there
/// is no library path to report. Callers that want to know whether the
/// provider is usable want [registerWebGpu], which answers on both platforms.
String? providerPath() => null;

/// Whether the runtime being served carries this provider.
///
/// Answered by asking the runtime, so it is right for whichever of the web
/// builds was bundled: an application that ships the CPU-only one gets false
/// here, which is the truth rather than an optimistic yes.
bool registerWebGpu() => availableProviders()
    .any((provider) => provider.toLowerCase().contains(providerName));

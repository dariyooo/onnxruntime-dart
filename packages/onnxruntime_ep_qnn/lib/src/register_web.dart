/// The provider on the web, where it is compiled in rather than loaded.
///
/// Nothing is registered here, and that is not a limitation being worked
/// around. The WebAssembly builds compile their accelerators in, so a provider
/// is either already present or was never built, and there is no third state
/// registering could reach.
///
/// QNN is not among what any web build carries, so this reports false. It
/// exists so that importing the package does not break a web build: an
/// application shipping both platforms can depend on it, ask, and be told no.
library;

import 'package:onnxruntime_dart/onnxruntime_dart.dart';

import 'identity.dart';

/// Null, always: nothing was installed as a file.
String? providerPath() => null;

/// Whether the runtime being served carries this provider.
///
/// Asked of the runtime rather than assumed, so that if a web build ever ships
/// with it this answers yes without anything here changing.
bool registerQnn() => availableProviders()
    .any((provider) => provider.toLowerCase().contains(providerName));

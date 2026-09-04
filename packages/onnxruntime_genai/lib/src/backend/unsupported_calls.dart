/// The web backend: refusals, and anywhere a refusal is not the right answer.
///
/// Upstream publishes no WebAssembly build of GenAI, so every call in
/// [GeneratedUnsupportedCalls] throws rather than pretending. The package still
/// compiles into a web application, which is what an application using GenAI on
/// native and something else on the web needs.
///
/// This file exists so that stops being all-or-nothing. If a call can be
/// answered on the web without GenAI at all, it is overridden here and the
/// refusal is replaced. `OgaShutdown` on a platform that never started is the
/// shape of that: doing nothing is a truer answer than throwing.
///
/// It names nothing native, which is what lets it be the web half of the
/// conditional export in calls.dart.
library;

import 'interface.dart';
import 'unsupported_generated.g.dart';

/// The backend for this platform.
GenAiCalls createCalls() => const UnsupportedGenAiCalls();

/// GenAI where there is no GenAI.
final class UnsupportedGenAiCalls
    with GeneratedUnsupportedCalls
    implements GenAiCalls {
  const UnsupportedGenAiCalls();

  /// Does nothing, rather than refusing.
  ///
  /// GenAI was never started here, so there is nothing to shut down and
  /// nothing has gone wrong. Refusing would make an application that releases
  /// its resources on the way out fail on the web for tidying up after work it
  /// never did, which is the opposite of what the refusals are for: they exist
  /// to stop a caller believing a model ran.
  @override
  void shutdown() {}
}

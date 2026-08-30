/// The seam, on the web.
///
/// Not implemented. The WebAssembly runtime builds, but nothing yet binds to
/// its exports. Everything above the seam is shared code and compiles for the
/// web today; only reaching the runtime fails, and it fails saying so rather
/// than at import time.
library;

import 'interface.dart';

/// Returns the backend for this platform.
OrtCalls createCalls() => throw UnsupportedError(
      'ONNX Runtime is not available on the web yet: the WebAssembly backend '
      'is not implemented. Everything that does not touch the runtime works.',
    );

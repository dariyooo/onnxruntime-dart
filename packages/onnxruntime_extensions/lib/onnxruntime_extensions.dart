/// Operators ONNX Runtime does not ship: tokenizers, text, image and audio
/// preprocessing that run inside the graph.
///
/// Native installs the library and this tells you where it is. A web build has
/// no loader for one, so [extensionsPath] answers null there and an
/// application checks rather than branching on the platform.
///
/// ```dart
/// final path = extensionsPath();
/// final session = Session.fromBytes(
///   bytes,
///   options: SessionOptions(customOpsLibraries: [if (path != null) path]),
/// );
/// ```
///
/// The split is a conditional export, resolved at compile time, so a web build
/// never references `dart:ffi`. Importing this package used to break one
/// outright.
library;

export 'src/identity.dart' show extensionsLibraryStem;
export 'src/path_ffi.dart' if (dart.library.js_interop) 'src/path_web.dart'
    show extensionsPath;

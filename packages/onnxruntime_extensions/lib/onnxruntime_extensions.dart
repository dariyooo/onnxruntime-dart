/// Operators ONNX Runtime does not ship: tokenizers, text, image and audio
/// preprocessing that run inside the graph.
///
/// This package installs the library and tells you where it is. The asset id
/// below has to be a compile-time constant, which is why the lookup lives here
/// rather than in onnxruntime_dart: only this package can name its own asset.
///
/// ```dart
/// final session = Session.fromBytes(
///   bytes,
///   options: SessionOptions(customOpsLibraries: [extensionsPath()!]),
/// );
/// ```
library;

import 'dart:ffi';

import 'package:onnxruntime_dart/native.dart';

/// The library's file name without prefix or extension.
const extensionsLibraryStem = 'ortextensions';

@Native<Void Function()>(
  symbol: 'RegisterCustomOps',
  assetId: 'package:onnxruntime_extensions_binaries/extensions',
)
external void _entryPoint();

/// Where the operator library was installed, or null if it was not.
String? extensionsPath() => loadedLibraryPath(
      () =>
          Native.addressOf<NativeFunction<Void Function()>>(_entryPoint).cast(),
      stem: extensionsLibraryStem,
    );

/// The operator library on a platform that loads libraries.
///
/// Installed as a file by onnxruntime_extensions_binaries, and found by asking
/// the loader where the asset landed. The asset id has to be a compile-time
/// constant, which is why this lives in the extensions package: only it can
/// name its own asset.
library;

import 'identity.dart';

import 'dart:ffi';

import 'package:onnxruntime_dart/native.dart';

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

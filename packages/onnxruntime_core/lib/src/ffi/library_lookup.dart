/// Finding a shared library that is already loaded.
///
/// ONNX Runtime opens providers and custom operator libraries by path, which
/// sits badly with code assets: they are bundled to be linked against, not to
/// be located, and Dart never says where one landed. The loader knows, though.
/// Take the address of a symbol the library exports and ask which file it came
/// from.
///
/// Nothing here knows what a provider is or which packages exist. A package
/// that ships a library declares its own asset, because the id in `@Native`
/// has to be a compile-time constant and can only be written where the asset
/// is, then uses this to find it.
library;

import 'dart:ffi';

import 'library_path.dart';

/// The file [entryPoint] came from, if its name contains [stem].
///
/// The name check is not optional. Every provider plugin exports the same
/// entry point, and a code asset that was not installed falls back to a
/// process-wide symbol lookup, so without it one library's path gets reported
/// for another and the runtime is handed the wrong file.
///
/// ```dart
/// @Native<Void Function()>(
///   symbol: 'CreateEpFactories',
///   assetId: 'package:my_provider/provider',
/// )
/// external void _entryPoint();
///
/// final path = loadedLibraryPath(
///   () => Native.addressOf<NativeFunction<Void Function()>>(_entryPoint).cast(),
///   stem: 'onnxruntime_providers_mine',
/// );
/// ```
String? loadedLibraryPath(
  Pointer<Void> Function() entryPoint, {
  required String stem,
}) {
  final Pointer<Void> address;
  try {
    address = entryPoint();
  } on ArgumentError {
    // No such asset in this build, which is the ordinary case for a package
    // the application does not depend on.
    return null;
  }

  final path = libraryPathOf(address);
  if (path == null) return null;

  final fileName = path.split(RegExp(r'[/\\]')).last;
  return fileName.contains(stem) ? path : null;
}

/// The operator library installed by the `onnxruntime_extensions` package.
///
/// Not a provider. A provider gives ONNX Runtime somewhere to run an operator
/// it already has; this gives it operators it does not: tokenizers, text,
/// image and audio preprocessing that would otherwise be rewritten in Dart.
/// It loads through `RegisterCustomOpsLibrary_V2`, which takes a path.
///
/// Finding that path is the same problem the providers have, and has the same
/// answer: take the address of a symbol the library exports and ask the loader
/// which file it came from. See [bundledProviderPath] for why a bare name is
/// not enough on every platform.
library;

import 'dart:ffi';

import 'library_path.dart';

/// The library name without prefix or extension.
///
/// Also what a discovered path is checked against, because a missing asset
/// falls back to a process-wide symbol lookup and would otherwise report
/// whichever other library happens to export the same entry point.
const _libraryStem = 'ortextensions';

@Native<Void Function()>(
  symbol: 'RegisterCustomOps',
  assetId: 'package:onnxruntime_extensions/extensions',
)
external void _registerCustomOps();

/// Where the extensions library was bundled, or null if it is not installed.
///
/// Pass it to a session:
///
/// ```dart
/// final path = extensionsLibraryPath();
/// final options = SessionOptions(
///   customOpsLibraries: [if (path != null) path],
/// );
/// ```
String? extensionsLibraryPath() {
  final Pointer<Void> address;
  try {
    address =
        Native.addressOf<NativeFunction<Void Function()>>(_registerCustomOps)
            .cast();
  } on ArgumentError {
    return null;
  }

  final path = libraryPathOf(address);
  if (path == null) return null;

  final fileName = path.split(RegExp(r'[/\\]')).last;
  return fileName.contains(_libraryStem) ? path : null;
}

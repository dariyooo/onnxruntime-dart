/// The two things the app asks the platform for.
///
/// Kept out of main.dart so the pages do not have to import the application to
/// reach them, which reads as a cycle even where the compiler allows it.
library;

import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:onnxruntime_dart/onnxruntime_dart.dart';
import 'package:onnxruntime_web_webgpu_webnn/onnxruntime_web_webgpu_webnn.dart';

import 'inference.dart';

/// Asks the platform for an image file.
///
/// Returns null when the person changed their mind, which is not an error.
Future<Uint8List?> pickImage() async {
  const kinds = XTypeGroup(
    label: 'images',
    extensions: ['jpg', 'jpeg', 'png', 'bmp', 'webp'],
  );
  final file = await openFile(acceptedTypeGroups: const [kinds]);
  if (file == null) return null;
  // Through the XFile rather than its path. In a browser the path is a blob
  // URL that no file API can open, and reading the XFile works on both.
  return file.readAsBytes();
}

/// The providers this build can be asked for.
///
/// Two different questions on the two platforms, which is why this is not one
/// call to `availableProviders`.
///
/// Native loads a provider as a library, so the runtime can enumerate what it
/// found and that list is the answer.
///
/// The web is not the same question. Providers are compiled into the build
/// rather than loaded, which is why there are three builds at all, but the
/// WebAssembly C API exports no call to enumerate them. So the backend can
/// only return what every build has, `CPUExecutionProvider` and
/// `XnnpackExecutionProvider`, and cannot see which of the three was served.
/// Asking it would offer CPU alone on a build carrying all three.
///
/// The only thing that knows is which package was depended on, which is what
/// `ortWebBuild` records.
List<ProviderChoice> providerChoices() {
  if (kIsWeb) {
    return [
      ProviderChoice.cpu,
      if (ortWebBuild.contains('webgpu')) ProviderChoice.webgpu,
      if (ortWebBuild.contains('webnn')) ProviderChoice.webnn,
    ];
  }
  final available = availableProviders();
  return [
    ProviderChoice.cpu,
    if (available.any((p) => p.toLowerCase().contains('webgpu')))
      ProviderChoice.webgpu,
  ];
}

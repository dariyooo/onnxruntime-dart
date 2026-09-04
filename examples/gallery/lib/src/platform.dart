/// The two things the app asks the platform for.
///
/// Kept out of main.dart so the pages do not have to import the application to
/// reach them, which reads as a cycle even where the compiler allows it.
library;

import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:onnxruntime_dart/onnxruntime_dart.dart';
import 'package:onnxruntime_ep_webgpu/onnxruntime_ep_webgpu.dart';

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
/// One question on both platforms. `registerWebGpu` loads the plugin on
/// native and reports whether the served runtime carries it on the web, so
/// asking it is both the check and the setup, and neither platform needs a
/// branch here.
///
/// WebNN has no plugin package because no native build carries it, so it is
/// asked of the runtime directly, which answers on the web builds that have
/// it compiled in.
List<ProviderChoice> providerChoices() => [
      ProviderChoice.cpu,
      if (registerWebGpu()) ProviderChoice.webgpu,
      if (availableProviders()
          .any((provider) => provider.toLowerCase().contains('webnn')))
        ProviderChoice.webnn,
    ];

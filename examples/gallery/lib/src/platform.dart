/// The two things the app asks the platform for.
///
/// Kept out of main.dart so the pages do not have to import the application to
/// reach them, which reads as a cycle even where the compiler allows it.
library;

import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:onnxruntime_dart/onnxruntime_dart.dart';

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
/// One question on both platforms now. Native lists what it loaded; the web
/// backend asks the module which accelerators were compiled into it, so a
/// build with WebGPU says so rather than reporting CPU and leaving the app to
/// guess from which package it depended on.
List<ProviderChoice> providerChoices() {
  final available = availableProviders().map((p) => p.toLowerCase()).toList();
  return [
    ProviderChoice.cpu,
    if (available.any((p) => p.contains('webgpu'))) ProviderChoice.webgpu,
    if (available.any((p) => p.contains('webnn'))) ProviderChoice.webnn,
  ];
}

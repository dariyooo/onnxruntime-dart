/// Execution providers installed by `onnxruntime_ep`.
///
/// A provider plugin is a shared library ONNX Runtime opens by path, which sits
/// awkwardly with code assets: they are bundled to be linked against, not to be
/// located. Two things make it work anyway.
///
/// ONNX Runtime resolves a relative library name against its own directory
/// (`core/session/utils.cc`, which asks the loader where `libonnxruntime`
/// itself came from). So wherever the plugin lands beside the runtime, its bare
/// file name is enough. That covers Dart standalone and Flutter on Linux,
/// Windows and Android, where every asset is placed in one directory.
///
/// Flutter on macOS and iOS is the exception: it repackages each asset into its
/// own framework, so they are no longer siblings. There the absolute path is
/// recovered from the loader instead, by taking the address of a symbol the
/// plugin exports and asking which file it came from.
library;

import 'dart:ffi';

import 'environment.dart';
import 'execution_provider.dart';
import 'library_path.dart';

/// An execution provider shipped as a separate library.
///
/// Providers compiled into the runtime, such as CPU, XNNPACK and CoreML, are
/// not here: they need no registration and are always present.
enum OrtExecutionProvider {
  /// GPU compute through WebGPU.
  webgpu('webgpu', 'onnxruntime_providers_webgpu'),

  /// NVIDIA GPUs. Needs the CUDA runtime on the machine.
  cuda('cuda', 'onnxruntime_providers_cuda'),

  /// NVIDIA TensorRT.
  tensorrt('tensorrt', 'onnxruntime_providers_tensorrt'),

  /// Qualcomm NPUs.
  qnn('qnn', 'onnxruntime_providers_qnn');

  const OrtExecutionProvider(this.registrationName, this.libraryStem);

  /// The name a session uses to ask for this provider.
  final String registrationName;

  /// The library name without prefix or extension.
  ///
  /// Used both to name the file for ONNX Runtime to resolve, and to check that
  /// a discovered path really is this provider.
  final String libraryStem;
}

/// `CreateEpFactories`, which every provider plugin must export.
///
/// Never called. Only the address is wanted: taking it is what makes the loader
/// reveal which file the plugin came from. Declaring an asset that nothing
/// provides is harmless, which is what lets every provider be offered while
/// only the installed ones resolve.
@Native<Void Function()>(
  symbol: 'CreateEpFactories',
  assetId: 'package:onnxruntime_ep/webgpu',
)
external void _webgpu();

@Native<Void Function()>(
  symbol: 'CreateEpFactories',
  assetId: 'package:onnxruntime_ep/cuda',
)
external void _cuda();

@Native<Void Function()>(
  symbol: 'CreateEpFactories',
  assetId: 'package:onnxruntime_ep/tensorrt',
)
external void _tensorrt();

@Native<Void Function()>(
  symbol: 'CreateEpFactories',
  assetId: 'package:onnxruntime_ep/qnn',
)
external void _qnn();

/// `Native.addressOf` takes the annotated function itself, so each provider
/// needs its own call rather than one over a variable.
Pointer<Void>? _addressOf(OrtExecutionProvider provider) {
  try {
    return switch (provider) {
      OrtExecutionProvider.webgpu =>
        Native.addressOf<NativeFunction<Void Function()>>(_webgpu),
      OrtExecutionProvider.cuda =>
        Native.addressOf<NativeFunction<Void Function()>>(_cuda),
      OrtExecutionProvider.tensorrt =>
        Native.addressOf<NativeFunction<Void Function()>>(_tensorrt),
      OrtExecutionProvider.qnn =>
        Native.addressOf<NativeFunction<Void Function()>>(_qnn),
    }
        .cast<Void>();
  } on ArgumentError {
    // Nothing publishes this asset and nothing in the process exports the
    // symbol, so this provider is not installed.
    return null;
  }
}

/// Where [provider] was installed, or null when it was not.
///
/// The file name is checked against the provider's own. Every plugin exports
/// the same entry point, so a missing asset falls back to whichever library in
/// the process exports it, and without the check an uninstalled provider would
/// report an unrelated library's path.
String? bundledProviderPath(OrtExecutionProvider provider) {
  final address = _addressOf(provider);
  if (address == null) return null;

  final path = libraryPathOf(address);
  if (path == null) return null;

  final fileName = path.split(RegExp(r'[/\\]')).last;
  return fileName.contains(provider.libraryStem) ? path : null;
}

/// Registers every provider `onnxruntime_ep` installed, and returns them.
///
/// A convenience over [registerExecutionProviderLibrary], which stays available
/// for a library built or placed by hand. Call before creating any session:
/// registration mutates process-global state, and racing it against session
/// creation crashes the runtime.
List<OrtExecutionProvider> registerBundledProviders() {
  final environment = OrtEnvironment.instance();
  final registered = <OrtExecutionProvider>[];

  for (final provider in OrtExecutionProvider.values) {
    final path = bundledProviderPath(provider);
    if (path == null) continue;

    registerExecutionProviderLibrary(
      environment.api,
      environment.handle,
      name: provider.registrationName,
      path: path,
    );
    registered.add(provider);
  }
  return registered;
}

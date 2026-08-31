/// Execution providers installed by the `onnxruntime_ep_*` packages.
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
import 'runtime.dart';

/// An execution provider shipped as a separate library.
///
/// Providers compiled into the runtime, such as CPU, XNNPACK and CoreML, are
/// not here: they need no registration and are always present.
enum OrtExecutionProvider {
  /// GPU compute through WebGPU.
  webgpu('webgpu', 'onnxruntime_providers_webgpu', '1.24.4'),

  /// NVIDIA GPUs. Needs the CUDA runtime on the machine.
  cuda('cuda', 'onnxruntime_providers_cuda', '1.24.4'),

  /// NVIDIA TensorRT.
  tensorrt('tensorrt', 'onnxruntime_providers_tensorrt', '1.24.4'),

  /// Qualcomm NPUs.
  qnn('qnn', 'onnxruntime_providers_qnn', '1.24.4');

  const OrtExecutionProvider(
    this.registrationName,
    this.libraryStem,
    this.minimumRuntime,
  );

  /// The name a session uses to ask for this provider.
  final String registrationName;

  /// The library name without prefix or extension.
  ///
  /// Used both to name the file for ONNX Runtime to resolve, and to check that
  /// a discovered path really is this provider.
  final String libraryStem;

  /// The oldest ONNX Runtime this provider works against.
  ///
  /// Taken from the plugin's own `MIN_ONNXRUNTIME_VERSION`, which ONNX Runtime
  /// compiles into the library and checks when it loads. Kept here as well so
  /// the mismatch can be reported before the runtime is asked to open a library
  /// it will refuse. `version_test.dart` holds this to the pinned tree.
  ///
  /// It is why each provider is its own package: a plugin outlives the runtime
  /// it shipped beside, so their versions cannot be the same.
  final String minimumRuntime;

  /// Whether this provider can run against [runtime], such as `1.29.0`.
  bool supportsRuntime(String runtime) {
    final wanted = minimumRuntime.split('.').map(int.parse).toList();
    final actual = runtime.split('.').map(int.parse).toList();
    for (var i = 0; i < wanted.length && i < actual.length; i++) {
      if (wanted[i] != actual[i]) return wanted[i] < actual[i];
    }
    return true;
  }
}

/// `CreateEpFactories`, which every provider plugin must export.
///
/// Never called. Only the address is wanted: taking it is what makes the loader
/// reveal which file the plugin came from. Declaring an asset that nothing
/// provides is harmless, which is what lets every provider be offered while
/// only the installed ones resolve.
@Native<Void Function()>(
  symbol: 'CreateEpFactories',
  assetId: 'package:onnxruntime_ep_webgpu/provider',
)
external void _webgpu();

@Native<Void Function()>(
  symbol: 'CreateEpFactories',
  assetId: 'package:onnxruntime_ep_cuda/provider',
)
external void _cuda();

@Native<Void Function()>(
  symbol: 'CreateEpFactories',
  assetId: 'package:onnxruntime_ep_tensorrt/provider',
)
external void _tensorrt();

@Native<Void Function()>(
  symbol: 'CreateEpFactories',
  assetId: 'package:onnxruntime_ep_qnn/provider',
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

/// Where [provider] was installed, or null when its package is not a
/// dependency.
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

/// Registers every provider package the application depends on, and returns
/// which ones were found.
///
/// A convenience over [registerExecutionProviderLibrary], which stays available
/// for a library built or placed by hand. Call before creating any session:
/// registration mutates process-global state, and racing it against session
/// creation crashes the runtime.
List<OrtExecutionProvider> registerBundledProviders() {
  final environment = OrtEnvironment.instance();
  final registered = <OrtExecutionProvider>[];

  final version = runtimeVersion();

  for (final provider in OrtExecutionProvider.values) {
    final path = bundledProviderPath(provider);
    if (path == null) continue;

    if (!provider.supportsRuntime(version)) {
      // The plugin checks this itself and would refuse, but only after the
      // runtime has opened it, and the message says less than this one.
      throw StateError(
        '${provider.name} needs ONNX Runtime ${provider.minimumRuntime} or '
        'newer, and this one is $version. Upgrade onnxruntime_binaries or '
        'onnxruntime_binaries, or depend on an older provider.',
      );
    }

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

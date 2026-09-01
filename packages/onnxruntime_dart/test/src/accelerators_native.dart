/// Accelerators on a native platform.
///
/// Each arrives as a plugin library that ships in its own package, so it has
/// to be registered before a session can name it, and it is only usable if the
/// machine actually has the device. CI has a GPU for none of them except
/// through software rendering, so most of these skip most of the time.
library;

import 'dart:io';

import 'package:onnxruntime_dart/onnxruntime_dart.dart';

import 'accelerator.dart';
import 'ort_library.dart';

export 'accelerator.dart';

/// Where CI puts each plugin, since no published Microsoft release ships one.
const _pluginVariables = {
  'webgpu': 'ONNXRUNTIME_EP_WEBGPU',
  'cuda': 'ONNXRUNTIME_EP_CUDA',
  'qnn': 'ONNXRUNTIME_EP_QNN',
};

/// The plugin library for [provider], or null if it was not supplied.
String? pluginPath(String provider) {
  final path = Platform.environment[_pluginVariables[provider]!];
  return path != null && File(path).existsSync() ? path : null;
}

final _registered = <String>{};

/// Registers the plugin for [provider]. Safe to call more than once.
Future<void> registerPlugin(String provider) async {
  if (!_registered.add(provider)) return;
  registerProviderLibrary(name: provider, path: pluginPath(provider)!);
}

List<Accelerator> accelerators() => [
      for (final provider in _pluginVariables.keys)
        Accelerator(
          label: provider,
          name: provider,
          ensure: () => registerPlugin(provider),
          skip: skipWithoutOrt ??
              (pluginPath(provider) == null
                  ? 'no $provider plugin (${_pluginVariables[provider]} unset)'
                  : null),
        ),
    ];

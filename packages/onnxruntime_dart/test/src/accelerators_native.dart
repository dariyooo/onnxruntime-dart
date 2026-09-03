/// Accelerators on a native platform.
///
/// Each arrives as a plugin library that ships in its own package, so it has
/// to be registered before a session can name it, and it is only usable if the
/// machine actually has the device. CI has a GPU for none of them except
/// through software rendering, so most of these skip most of the time.
library;

import 'dart:io';

import 'package:onnxruntime_dart/native.dart';
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

/// Whether [provider] registered and contributed a device to run on.
///
/// Loading a plugin and having hardware for it are different things. CUDA
/// loads on a machine with the CUDA runtime and no GPU; QNN loads anywhere its
/// mirror put the Qualcomm runtime and finds no NPU. Neither can run a model,
/// so neither belongs in a list of accelerators to run models on.
/// `plugin_load_test.dart` is what proves they load.
bool _hasDevice(String provider) {
  if (pluginPath(provider) == null) return false;
  try {
    // Registered here rather than through registerPlugin, which is async: an
    // exception from a future is not caught by a try around the call, and a
    // plugin that cannot load would take the whole suite down at load time
    // instead of being reported as absent.
    if (_registered.add(provider)) {
      registerProviderLibrary(name: provider, path: pluginPath(provider)!);
    }
  } on Object {
    _registered.remove(provider);
    return false;
  }
  final environment = OrtEnvironment.instance();
  return executionProviderDeviceNames(environment.api, environment.handle)
      .any((name) => name.toLowerCase().contains(provider.toLowerCase()));
}

/// Providers that enumerate a device without being able to use it.
///
/// QNN contributes a device wherever its plugin loads, because the plugin
/// carries the Qualcomm runtime, and then fails at session creation with
/// "Could not determine default backend path" because there is no NPU behind
/// it. Having a device is therefore not proof of being usable, and no hosted
/// runner has the hardware, so it is load-tested and never run.
/// `plugin_load_test.dart` is what covers it.
const _neverRunnable = {'qnn'};

/// The providers this machine can actually run a model on.
///
/// Filtered rather than skipped: a provider with no hardware behind it is not
/// a test that did not run, it is a test that does not apply here.
List<Accelerator> accelerators() => [
      for (final provider in _pluginVariables.keys)
        if (!_neverRunnable.contains(provider) &&
            skipWithoutOrt == null &&
            skipWithoutNativeAsset == null &&
            _hasDevice(provider))
          Accelerator(
            label: provider,
            name: provider,
            ensure: () => registerPlugin(provider),
          ),
    ];

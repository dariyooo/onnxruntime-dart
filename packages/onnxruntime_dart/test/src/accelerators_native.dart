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
import 'embedded_model.dart';
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

/// Whether [provider] can actually build a session, not merely appear.
///
/// Enumerating a device is not the same as being able to use one. QNN
/// contributes a device wherever its plugin loads, because the plugin carries
/// the Qualcomm runtime, and then fails with "Could not determine default
/// backend path" for want of an NPU. WebGPU on Windows ARM enumerates an
/// adapter and then fails to initialise Dawn. Both look identical to a device
/// count, and neither can run a model.
///
/// So the question asked here is the one the tests actually depend on: does a
/// session on this provider build? What it costs is one session; what it buys
/// is that a provider is excluded for the reason it cannot be used, rather
/// than by a list of platforms someone has to maintain.
///
/// `plugin_load_test.dart` remains the proof that each plugin loads, which is
/// a different claim and worth keeping separate.
bool _canRunOn(String provider) {
  if (pluginPath(provider) == null) return false;
  try {
    // Registered here rather than through registerPlugin, which is async: an
    // exception from a future is not caught by a try around the call, and a
    // plugin that cannot load would take the whole suite down at load time
    // instead of being reported as absent.
    if (_registered.add(provider)) {
      registerProviderLibrary(name: provider, path: pluginPath(provider)!);
    }
    final session = Session.fromBytes(
      absModel(),
      options: SessionOptions(
        providers: [(name: provider, configuration: const {})],
      ),
    );
    session.release();
    return true;
  } on Object catch (error) {
    // Printed rather than swallowed: an accelerator quietly dropping off the
    // list is how a real regression would hide as a platform limitation.
    print('$provider is not usable here: $error');
    return false;
  }
}

List<Accelerator> accelerators() => [
      for (final provider in _pluginVariables.keys)
        if (skipWithoutOrt == null &&
            skipWithoutNativeAsset == null &&
            _canRunOn(provider))
          Accelerator(
            label: provider,
            name: provider,
            ensure: () => registerPlugin(provider),
          ),
    ];

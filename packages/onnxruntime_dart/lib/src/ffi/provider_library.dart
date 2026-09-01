/// Registering an execution provider that some package installed.
///
/// Nothing here knows which providers exist. A provider package declares its
/// own asset and describes itself with [BundledProvider]; this takes that
/// description and hands ONNX Runtime the path. Adding a provider is a new
/// package and no change to this one.
///
/// The path is the awkward part, and why a description is needed at all.
/// ONNX Runtime opens a plugin by path, which sits badly with code assets:
/// they are bundled to be linked against, not to be located. Two things make
/// it work.
///
/// ONNX Runtime resolves a relative library name against its own directory, so
/// wherever the plugin lands beside the runtime its bare file name is enough.
/// That covers Dart standalone and Flutter on Linux, Windows and Android,
/// where every asset goes in one directory. Flutter on macOS and iOS is the
/// exception: it repackages each asset into its own framework, so they are no
/// longer siblings, and there the absolute path is recovered from the loader.
library;

import 'dart:ffi';

import 'environment.dart';
import 'execution_provider.dart';
import 'library_path.dart';
import 'runtime.dart';

/// A provider library installed by a package, as that package describes it.
///
/// Built by the provider package, which is the only place that can: the asset
/// id in `@Native` has to be a compile-time constant, so it can only be
/// written where the asset lives.
final class BundledProvider {
  const BundledProvider({
    required this.name,
    required this.libraryStem,
    required this.entryPoint,
    this.minimumRuntime,
  });

  /// The name a session uses to ask for this provider, such as `webgpu`.
  final String name;

  /// The library's file name without prefix or extension.
  ///
  /// Used to check that a discovered path really is this provider. Every
  /// plugin exports the same entry point, and a missing asset falls back to a
  /// process-wide symbol lookup, so without this check one provider's path
  /// would be reported for another.
  final String libraryStem;

  /// The address of a symbol the library exports, from which the loader can
  /// name the file it came from.
  final Pointer<Void> Function() entryPoint;

  /// The oldest ONNX Runtime this provider works against, if it declares one.
  final String? minimumRuntime;
}

/// Where [provider] was bundled, or null if it is not installed.
String? bundledProviderPath(BundledProvider provider) {
  final Pointer<Void> address;
  try {
    address = provider.entryPoint();
  } on ArgumentError {
    return null;
  }

  final path = libraryPathOf(address);
  if (path == null) return null;

  final fileName = path.split(RegExp(r'[/\\]')).last;
  return fileName.contains(provider.libraryStem) ? path : null;
}

/// Registers [providers] that are actually installed, and returns those.
///
/// Call before creating any session: registration mutates process-global
/// state, and racing it against session creation crashes the runtime.
List<BundledProvider> registerBundledProviders(
  List<BundledProvider> providers,
) {
  final environment = OrtEnvironment.instance();
  final version = runtimeVersion();
  final registered = <BundledProvider>[];

  for (final provider in providers) {
    final path = bundledProviderPath(provider);
    if (path == null) continue;

    final minimum = provider.minimumRuntime;
    if (minimum != null && !_atLeast(version, minimum)) {
      // Installed but unusable. Silence would look like "not installed", and
      // the fix is different: upgrade the runtime or downgrade the provider.
      throw StateError(
        '${provider.name} needs ONNX Runtime $minimum or newer, and this one '
        'is $version. Upgrade onnxruntime_binaries, or depend on a provider '
        'version that matches it.',
      );
    }

    registerExecutionProviderLibrary(
      environment.api,
      environment.handle,
      name: provider.name,
      path: path,
    );
    registered.add(provider);
  }
  return registered;
}

/// Whether [version] is at least [minimum], comparing the numeric parts.
bool _atLeast(String version, String minimum) {
  int part(String value, int index) {
    final parts = value.split('.');
    if (index >= parts.length) return 0;
    return int.tryParse(RegExp(r'^\d+').stringMatch(parts[index]) ?? '') ?? 0;
  }

  for (var i = 0; i < 3; i++) {
    final have = part(version, i);
    final need = part(minimum, i);
    if (have != need) return have > need;
  }
  return true;
}

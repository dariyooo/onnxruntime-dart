/// Maps a build target to the prebuilt library we publish for it.
///
/// Kept free of `dart:io` and of the hook APIs so the mapping can be tested
/// directly rather than only through a build.
library;

import 'package:code_assets/code_assets.dart';

/// Thrown when no prebuilt library exists for a target.
final class UnsupportedTarget implements Exception {
  UnsupportedTarget(this.os, this.architecture, [this.detail]);

  final OS os;
  final Architecture architecture;
  final String? detail;

  @override
  String toString() =>
      'onnxruntime_dart has no prebuilt library for $os $architecture'
      '${detail == null ? '' : ' ($detail)'}. Supported targets: '
      '${supportedTargets.join(', ')}.';
}

/// The libraries we publish per platform.
///
/// [base] carries every operator and every provider we build, which is what
/// almost every app wants. [full] adds what cannot be loaded at run time, which
/// today is on-device training.
enum OrtVariant {
  base(''),
  full('-full');

  const OrtVariant(this.suffix);

  /// Appended to a target identifier to name the asset.
  final String suffix;

  static OrtVariant byName(String name) => values.firstWhere(
        (v) => v.name == name,
        orElse: () => throw ArgumentError.value(
          name,
          'variant',
          'expected one of ${values.map((v) => v.name).join(', ')}',
        ),
      );
}

/// Identifiers of every configuration we build, matching the release assets.
const supportedTargets = <String>[
  'android-arm64-v8a',
  'android-armeabi-v7a',
  'android-x86_64',
  'android-x86',
  'ios-device-arm64',
  'ios-sim-arm64',
  'ios-sim-x86_64',
  'linux-arm64',
  'linux-x64',
  'macos-arm64',
  'macos-x86_64',
  'windows-arm64',
  'windows-x64',
];

/// The configuration identifier for a target.
///
/// [iosSdk] distinguishes an iOS device build from a simulator build, which are
/// different artifacts for the same architecture. [variant] selects which
/// library, and defaults to the one almost every app wants.
String targetId({
  required OS os,
  required Architecture architecture,
  IOSSdk? iosSdk,
  OrtVariant variant = OrtVariant.base,
}) {
  final id = switch ((os, architecture)) {
    (OS.android, Architecture.arm64) => 'android-arm64-v8a',
    (OS.android, Architecture.arm) => 'android-armeabi-v7a',
    (OS.android, Architecture.x64) => 'android-x86_64',
    (OS.android, Architecture.ia32) => 'android-x86',
    (OS.iOS, Architecture.arm64) => switch (iosSdk) {
        IOSSdk.iPhoneOS => 'ios-device-arm64',
        IOSSdk.iPhoneSimulator => 'ios-sim-arm64',
        _ => throw UnsupportedTarget(
            os,
            architecture,
            'iOS builds must say whether they target a device or the simulator',
          ),
      },
    // The simulator is the only place an x64 iOS build runs.
    (OS.iOS, Architecture.x64) => 'ios-sim-x86_64',
    (OS.linux, Architecture.x64) => 'linux-x64',
    (OS.linux, Architecture.arm64) => 'linux-arm64',
    (OS.macOS, Architecture.arm64) => 'macos-arm64',
    (OS.macOS, Architecture.x64) => 'macos-x86_64',
    (OS.windows, Architecture.x64) => 'windows-x64',
    (OS.windows, Architecture.arm64) => 'windows-arm64',
    _ => throw UnsupportedTarget(os, architecture),
  };
  assert(supportedTargets.contains(id));
  return '$id${variant.suffix}';
}

/// File name of the shared library on [os].
String libraryFileName(OS os) => switch (os) {
      OS.windows => 'onnxruntime.dll',
      OS.macOS || OS.iOS => 'libonnxruntime.dylib',
      _ => 'libonnxruntime.so',
    };

/// Release asset holding the library for [targetId].
/// Where every asset this hook downloads is published.
const _releases =
    'https://github.com/dariyooo/onnxruntime-dart/releases/download';

/// The published name of the runtime asset for [targetId].
///
/// Component first, the way every other asset is named: `base-linux-x64` and
/// `full-linux-x64` beside `webgpu-linux-x64` and `extensions-linux-x64`. The
/// identifier still carries the variant as a suffix, because that is how it is
/// keyed everywhere else, so it is moved to the front here rather than
/// threaded through every caller.
String assetFileName(String targetId) {
  const full = '-full';
  return targetId.endsWith(full)
      ? 'full-${targetId.substring(0, targetId.length - full.length)}.tar.gz'
      : 'base-$targetId.tar.gz';
}

/// URL of the release asset for [targetId] at [releaseTag].
Uri assetUrl({required String releaseTag, required String targetId}) =>
    Uri.parse('$_releases/$releaseTag/${assetFileName(targetId)}');

/// An execution provider shipped as a separate loadable library.
///
/// Providers compiled into the runtime, such as CPU, XNNPACK and CoreML, are
/// not here: they are always present and need no installing.
///
/// Availability is per target because the hardware is. Asking for one where it
/// does not exist is a mistake worth hearing at build time, rather than a
/// session that quietly falls back to the CPU.
enum OrtProvider {
  /// GPU compute through WebGPU, built alongside our own runtime.
  webgpu('onnxruntime_providers_webgpu'),

  /// NVIDIA GPUs. Redistributed from ONNX Runtime's own plugin release rather
  /// than built here: it takes hours to compile and needs the CUDA toolkit.
  cuda('onnxruntime_providers_cuda'),

  /// NVIDIA TensorRT. Not published by us: upstream ships it only inside
  /// onnxruntime-gpu, in the older provider-bridge form, so there is nothing
  /// plugin-shaped to mirror. Kept so a hand-placed library still has a name.
  tensorrt('onnxruntime_providers_tensorrt'),

  /// Qualcomm NPUs, redistributed from the wheel ONNX Runtime publishes.
  /// Building it is not an option: the Qualcomm SDK it links against is behind
  /// an authenticated download, and the wheel carries that SDK's runtime with
  /// a licence to pass it on.
  qnn('onnxruntime_providers_qnn');

  const OrtProvider(this.libraryStem);

  /// The library name without prefix or extension.
  final String libraryStem;

  /// The builds published for this provider, or empty when there is only one.
  ///
  /// CUDA ships against two toolkits. They do the same thing and differ in
  /// what they ask of the machine, so which to install is the application's
  /// choice rather than ours.
  List<String> get builds => switch (this) {
        OrtProvider.cuda => const ['cuda12', 'cuda13'],
        _ => const [],
      };

  /// The build preferred when the application does not say.
  ///
  /// CUDA 12 for CUDA, because CUDA 13 needs an R580 driver and drops Maxwell,
  /// Pascal and Volta. An old card runs CUDA 12 happily, a machine nobody has
  /// updated runs only CUDA 12, and that is the common case. CUDA 13 is around
  /// half the size and is one line away.
  ///
  /// A preference, not a guarantee: see [buildFor], which is what installs.
  String? get defaultBuild => switch (this) {
        OrtProvider.cuda => 'cuda12',
        _ => null,
      };

  /// The build to install for [target] when the application does not say.
  ///
  /// The preferred build is not published everywhere. Upstream builds CUDA 12
  /// for x64 only, so on arm64 the preference cannot be honoured and the only
  /// build that exists there is the right one to take. Falling back beats
  /// failing, because the alternative is telling somebody their platform is
  /// unsupported when a provider for it is sitting in the release.
  String? buildFor(String target) {
    if (builds.isEmpty) return null;
    if (targetsFor(defaultBuild).contains(target)) return defaultBuild;
    return builds.firstWhere(
      (b) => targetsFor(b).contains(target),
      orElse: () => defaultBuild!,
    );
  }

  /// Targets [build] is published for.
  ///
  /// Only CUDA 13 exists for arm64 upstream, so asking for 12 there is a
  /// mistake worth naming rather than a download that will not be found.
  List<String> targetsFor(String? build) => switch ((this, build)) {
        (OrtProvider.cuda, 'cuda12') => const ['linux-x64', 'windows-x64'],
        _ => targets,
      };

  static OrtProvider byName(String name) => values.firstWhere(
        (p) => p.name == name,
        orElse: () => throw ArgumentError.value(
          name,
          'provider',
          'expected one of ${values.map((p) => p.name).join(', ')}',
        ),
      );

  /// Targets this provider is published for.
  List<String> get targets => switch (this) {
        // Ours, and everywhere Dawn reaches a GPU: Vulkan on Linux and
        // Android, D3D12 or Vulkan on Windows, Metal on Apple. On Android it
        // replaces NNAPI, which was deprecated in Android 15.
        //
        // Not the 32-bit Android ABIs, where Vulkan is not dependable on the
        // hardware still running them. Not iOS either: Dawn's Objective-C is
        // written for manual reference counting and ONNX Runtime's iOS
        // toolchain forces ARC on, so it does not compile there.
        OrtProvider.webgpu => const [
            'android-arm64-v8a',
            'android-x86_64',
            'ios-device-arm64',
            'ios-sim-arm64',
            'ios-sim-x86_64',
            'linux-x64',
            'linux-arm64',
            'macos-arm64',
            'macos-x86_64',
            'windows-x64',
            'windows-arm64',
          ],
        // What ONNX Runtime's own plugin release publishes. No macOS, and
        // nothing mobile: NVIDIA hardware is desktop and server only.
        OrtProvider.cuda || OrtProvider.tensorrt => const [
            'linux-x64',
            'linux-arm64',
            'windows-x64',
            'windows-arm64',
          ],
        // What the wheels cover. Not Android: there QNN is linked into a
        // whole runtime rather than published as a plugin, so it cannot layer
        // on ours. The x64 hosts have no NPU and are there to compile graphs
        // ahead of time for one that does.
        OrtProvider.qnn => const [
            'linux-x64',
            'linux-arm64',
            'windows-x64',
            'windows-arm64',
          ],
      };

  /// Whether this provider exists for [target].
  bool isAvailableOn(String target) => targets.contains(target);

  /// The file name to install.
  ///
  /// Also what ONNX Runtime looks for when handed a relative name: it resolves
  /// one against its own directory, so the name has to be exact.
  String libraryFileName(OS os) => switch (os) {
        OS.windows => '$libraryStem.dll',
        OS.macOS || OS.iOS => 'lib$libraryStem.dylib',
        _ => 'lib$libraryStem.so',
      };
}

/// Release asset holding [provider] for [targetId].
///
/// [build] distinguishes providers that do the same thing but ask different
/// things of the machine, such as which CUDA toolkit is installed. Providers
/// with only one build leave it out.
/// The onnxruntime-extensions operator library, which is not a provider.
///
/// A provider gives ONNX Runtime somewhere to run an operator it already has.
/// This gives it operators it does not: tokenizers, text, image and audio
/// preprocessing that would otherwise be rewritten in Dart. It loads through
/// `RegisterCustomOpsLibrary_V2` rather than the provider machinery.
abstract final class OrtExtensions {
  /// The library name without prefix or extension.
  static const libraryStem = 'ortextensions';

  /// Every native target. Not the web, where the library cannot be shared:
  /// under Emscripten the operators have to be compiled into the runtime.
  static List<String> get targets =>
      supportedTargets.where((t) => !t.startsWith('web-')).toList();

  static bool isAvailableOn(String target) => targets.contains(target);

  static String fileName(OS os) => switch (os) {
        OS.windows => '$libraryStem.dll',
        OS.macOS || OS.iOS => 'lib$libraryStem.dylib',
        _ => 'lib$libraryStem.so',
      };
}

/// Asset name for the extensions library on [targetId].
String extensionsAssetFileName(String targetId) =>
    'extensions-$targetId.tar.gz';

/// URL of the extensions asset for [targetId] at [releaseTag].
Uri extensionsAssetUrl({
  required String releaseTag,
  required String targetId,
}) =>
    Uri.parse('$_releases/$releaseTag/${extensionsAssetFileName(targetId)}');

String providerAssetFileName(String provider, String targetId,
        {String? build}) =>
    build == null
        ? '$provider-$targetId.tar.gz'
        : '$provider-$build-$targetId.tar.gz';

/// URL of the provider asset for [targetId] at [releaseTag].
Uri providerAssetUrl({
  required String releaseTag,
  required String provider,
  required String targetId,
  String? build,
}) =>
    Uri.parse(
      '$_releases/$releaseTag/'
      '${providerAssetFileName(provider, targetId, build: build)}',
    );

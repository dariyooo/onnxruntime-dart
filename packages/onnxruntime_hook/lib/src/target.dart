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
String assetFileName(String targetId) => '$targetId.tar.gz';

/// URL of the release asset for [targetId] at [releaseTag].
Uri assetUrl({required String releaseTag, required String targetId}) =>
    Uri.parse(
      'https://github.com/dariyooo/onnxruntime-dart/releases/download'
      '/$releaseTag/${assetFileName(targetId)}',
    );

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

  /// NVIDIA TensorRT, redistributed for the same reason.
  tensorrt('onnxruntime_providers_tensorrt'),

  /// Qualcomm NPUs.
  qnn('onnxruntime_providers_qnn');

  const OrtProvider(this.libraryStem);

  /// The library name without prefix or extension.
  final String libraryStem;

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
        OrtProvider.qnn => const ['android-arm64-v8a', 'windows-arm64'],
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
String providerAssetFileName(String provider, String targetId) =>
    '$provider-$targetId.tar.gz';

/// URL of the provider asset for [targetId] at [releaseTag].
Uri providerAssetUrl({
  required String releaseTag,
  required String provider,
  required String targetId,
}) =>
    Uri.parse(
      'https://github.com/dariyooo/onnxruntime-dart/releases/download'
      '/$releaseTag/${providerAssetFileName(provider, targetId)}',
    );

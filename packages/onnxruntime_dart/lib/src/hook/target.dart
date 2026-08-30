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
/// different artifacts for the same architecture.
String targetId({
  required OS os,
  required Architecture architecture,
  IOSSdk? iosSdk,
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
  return id;
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

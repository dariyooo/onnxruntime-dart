/// The build hook the runtime packages share.
///
/// `onnxruntime_base` and `onnxruntime_full` differ only in which
/// library they install, so the work lives here and each of them is a few lines
/// naming its variant. Neither package holds a binary: the library is fetched
/// from the release named for the package's own version, which is the ONNX
/// Runtime version.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

import 'target.dart';

/// Declares the ONNX Runtime library for the target being built.
///
/// Call from a runtime package's `hook/build.dart`. [variant] says which
/// library to install, and the asset is named for the calling package, so the
/// bindings can tell base from full by which id resolves.
Future<void> installRuntime(List<String> args, OrtVariant variant) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;

    final code = input.config.code;
    final target = targetId(
      os: code.targetOS,
      architecture: code.targetArchitecture,
      iosSdk: code.targetOS == OS.iOS ? code.iOS.targetSdk : null,
      variant: variant,
    );

    final library = await _resolve(input, target, code.targetOS);
    if (library == null) return;

    output.assets.code.add(
      CodeAsset(
        package: input.packageName,
        name: 'onnxruntime',
        linkMode: DynamicLoadingBundled(),
        file: library.uri,
      ),
    );
  });
}

/// The release this package installs from, named for its own version.
///
/// The package version is the ONNX Runtime version, so `1.29.1` installs the
/// binaries built from ONNX Runtime 1.29.1. Nothing is generated and there is
/// no second copy to drift.
String releaseTag(BuildInput input) {
  final pubspec = File.fromUri(input.packageRoot.resolve('pubspec.yaml'));
  final match = RegExp(
    r'^version:\s*(\d+\.\d+\.\d+\S*)\s*$',
    multiLine: true,
  ).firstMatch(pubspec.readAsStringSync());

  if (match == null) {
    throw StateError(
      '${input.packageName}: ${pubspec.path} has no version, so there is no '
      'way to tell which ONNX Runtime release to install.',
    );
  }
  return 'runtime-v${match.group(1)}';
}

/// Finds the library: a local build if one was configured, then a previous
/// download, then the release.
Future<File?> _resolve(BuildInput input, String target, OS os) async {
  final fileName = libraryFileName(os);

  final override = input.userDefines.path('local_build');
  if (override != null) {
    final file = File.fromUri(_asDirectory(override).resolve(fileName));
    if (file.existsSync()) return file;

    // Asking for a local build and not having one is a mistake, but failing
    // outright would also block `dart analyze` and the pure-Dart tests, which
    // is how someone gets far enough to build one.
    stderr.writeln(
      '${input.packageName}: local_build points at $override, which holds no '
      '$fileName. Expected a directory containing the shared library.\n'
      'Continuing without a native library.',
    );
    return null;
  }

  final tag = releaseTag(input);

  // Keyed by release, so bumping the package downloads that runtime rather
  // than reusing whatever the last one left here.
  final cached = File.fromUri(
    input.outputDirectoryShared.resolve('$tag/$target/$fileName'),
  );
  if (cached.existsSync()) return cached;

  return _download(
    url: assetUrl(releaseTag: tag, targetId: target),
    into: cached,
    fileName: fileName,
    target: target,
    package: input.packageName,
  );
}

Future<File> _download({
  required Uri url,
  required File into,
  required String fileName,
  required String target,
  required String package,
}) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
  final Uint8List archive;
  try {
    final response = await (await client.getUrl(url)).close();
    if (response.statusCode == HttpStatus.notFound) {
      throw StateError(
        '$package publishes no $target build at $url.\n'
        'Either that release does not exist yet, or it does not cover this '
        'target. Point the hook at your own build instead:\n'
        '\n'
        '  # pubspec.yaml\n'
        '  hooks:\n'
        '    user_defines:\n'
        '      $package:\n'
        '        local_build: path/to/directory/containing/$fileName\n',
      );
    }
    if (response.statusCode != HttpStatus.ok) {
      throw StateError('$package could not download $url: '
          'HTTP ${response.statusCode}');
    }
    final builder = BytesBuilder(copy: false);
    await response.forEach(builder.add);
    archive = builder.takeBytes();
  } on IOException catch (e) {
    throw StateError('$package could not download $url: $e');
  } finally {
    client.close(force: true);
  }

  into.parent.createSync(recursive: true);
  await into.writeAsBytes(_extractLibrary(archive, fileName), flush: true);
  return into;
}

/// Pulls [fileName] out of a gzipped tar archive.
Uint8List _extractLibrary(Uint8List archive, String fileName) {
  const blockSize = 512;
  final tar = Uint8List.fromList(gzip.decode(archive));
  var offset = 0;

  while (offset + blockSize <= tar.length) {
    final header = Uint8List.sublistView(tar, offset, offset + blockSize);
    final name = _tarField(header, 0, 100);
    if (name.isEmpty) break;

    final sizeField = _tarField(header, 124, 12);
    final size = sizeField.isEmpty ? 0 : int.parse(sizeField, radix: 8);
    offset += blockSize;

    if (offset + size > tar.length) {
      throw StateError('truncated archive at entry $name');
    }
    if (name.split('/').last == fileName) {
      return Uint8List.fromList(
        Uint8List.sublistView(tar, offset, offset + size),
      );
    }
    offset += (size + blockSize - 1) & ~(blockSize - 1);
  }
  throw StateError('archive holds no $fileName');
}

/// Uri.resolve replaces the last segment unless the base ends in a slash, so a
/// directory given without one would silently resolve against its parent.
Uri _asDirectory(Uri uri) =>
    uri.path.endsWith('/') ? uri : uri.replace(path: '${uri.path}/');

String _tarField(Uint8List header, int start, int maxLength) {
  var end = start;
  while (end < start + maxLength && header[end] != 0) {
    end++;
  }
  return utf8.decode(Uint8List.sublistView(header, start, end)).trim();
}

/// Declares the execution provider libraries the application asked for.
///
/// Call from `onnxruntime_ep`'s `hook/build.dart`. Providers are named in
/// user-defines, and each becomes its own code asset so the Dart side can tell
/// which ones were installed:
///
/// ```yaml
/// hooks:
///   user_defines:
///     onnxruntime_ep:
///       providers: [cuda, webgpu]
/// ```
///
/// A provider that this build does not publish for the target is an error
/// rather than a silent omission: asking for CUDA on Android is a mistake worth
/// hearing about at build time, not a session that quietly runs on the CPU.
Future<void> installProviders(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;

    final requested = _requestedProviders(input);
    if (requested.isEmpty) return;

    final code = input.config.code;
    final target = targetId(
      os: code.targetOS,
      architecture: code.targetArchitecture,
      iosSdk: code.targetOS == OS.iOS ? code.iOS.targetSdk : null,
    );

    for (final provider in requested) {
      if (!provider.isAvailableOn(target)) {
        throw StateError(
          'onnxruntime_ep: there is no ${provider.name} provider for $target. '
          'It is published for ${provider.targets.join(', ')}. Remove it, or '
          'select it only on the platforms that have it.',
        );
      }

      final library =
          await _resolveProvider(input, provider, target, code.targetOS);
      if (library == null) continue;

      output.assets.code.add(
        CodeAsset(
          package: input.packageName,
          name: provider.name,
          linkMode: DynamicLoadingBundled(),
          file: library.uri,
        ),
      );
    }
  });
}

List<OrtProvider> _requestedProviders(BuildInput input) {
  final names = input.userDefines['providers'];
  if (names == null) return const [];
  if (names is! List) {
    throw StateError(
      'onnxruntime_ep: providers must be a list, got ${names.runtimeType}. '
      'For example: providers: [cuda, webgpu]',
    );
  }
  return [for (final name in names) OrtProvider.byName('$name')];
}

/// Finds a provider library the same way the runtime is found.
Future<File?> _resolveProvider(
  BuildInput input,
  OrtProvider provider,
  String target,
  OS os,
) async {
  final fileName = provider.libraryFileName(os);

  final override = input.userDefines.path('local_build');
  if (override != null) {
    final file = File.fromUri(_asDirectory(override).resolve(fileName));
    if (file.existsSync()) return file;
    stderr.writeln(
      'onnxruntime_ep: local_build holds no $fileName, so ${provider.name} '
      'is not installed.',
    );
    return null;
  }

  final tag = releaseTag(input);
  final cached = File.fromUri(
    input.outputDirectoryShared.resolve('$tag/$target/$fileName'),
  );
  if (cached.existsSync()) return cached;

  return _download(
    url: providerAssetUrl(
      releaseTag: tag,
      provider: provider.name,
      targetId: target,
    ),
    into: cached,
    fileName: fileName,
    target: target,
    package: input.packageName,
  );
}

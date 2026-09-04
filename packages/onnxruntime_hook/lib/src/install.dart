/// The build hook the runtime packages share.
///
/// `onnxruntime_binaries` and `onnxruntime_binaries` differ only in which
/// library they install, so the work lives here and each of them is a few lines
/// naming its variant. Neither package holds a binary: the library is fetched
/// from the release named for the package's own version, which is the ONNX
/// Runtime version.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:code_assets/code_assets.dart';
import 'package:crypto/crypto.dart';
import 'package:hooks/hooks.dart';

import 'target.dart';

/// Declares the ONNX Runtime library for the target being built.
///
/// The variant comes from user-defines rather than from which package was
/// depended on, because exactly one may be installed and pub cannot express
/// that two packages are mutually exclusive:
///
/// ```yaml
/// hooks:
///   user_defines:
///     onnxruntime_binaries:
///       variant: full
/// ```
Future<void> installRuntime(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;

    final variant = _variant(input);

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
/// Every package here is versioned as the thing it contains, and the release it
/// downloads from is named the same way. The runtime packages carry the ONNX
/// Runtime version; each provider carries its own, because ONNX Runtime
/// versions its plugins separately and they outlive a runtime release. Nothing
/// is generated, and there is no second copy to drift.
String releaseTag(BuildInput input, {String component = 'runtime'}) {
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
  return '$component-v${match.group(1)}';
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

const _timeout = Duration(seconds: 30);

Future<File> _download({
  required Uri url,
  required File into,
  required String fileName,
  required String target,
  required String package,
}) async {
  final client = HttpClient()..connectionTimeout = _timeout;
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

  await _verify(archive, url: url, package: package, client: null);

  into.parent.createSync(recursive: true);
  await into.writeAsBytes(_extractLibrary(archive, fileName), flush: true);
  return into;
}

/// Checks an archive against the SHA-256 published beside it.
///
/// Every release carries a `.sha256` sidecar per asset. Without this the hook
/// installs whatever the network returned, which is the one step in the chain
/// where bytes we did not build could get in.
///
/// A missing sidecar is not fatal: releases cut before the sidecars existed
/// still have to install. A sidecar that disagrees is.
Future<void> _verify(
  Uint8List archive, {
  required Uri url,
  required String package,
  HttpClient? client,
}) async {
  final http = client ?? (HttpClient()..connectionTimeout = _timeout);
  String? published;
  try {
    final response =
        await (await http.getUrl(Uri.parse('$url.sha256'))).close();
    if (response.statusCode != HttpStatus.ok) return;
    final builder = BytesBuilder(copy: false);
    await response.forEach(builder.add);
    published =
        utf8.decode(builder.takeBytes()).trim().split(RegExp(r'\s+')).first;
  } on IOException {
    return;
  } finally {
    if (client == null) http.close(force: true);
  }

  final actual = sha256.convert(archive).toString();
  if (published.isEmpty || published == actual) return;

  throw StateError(
    '$package: $url does not match the SHA-256 published beside it.\n'
    '  expected \$published\n'
    '  actual   \$actual\n'
    'Refusing to install it.',
  );
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

/// Declares the execution provider library this package installs.
///
/// Call from an `onnxruntime_ep_*` package's `hook/build.dart`. One provider
/// per package, chosen by depending on it, so there is no list to configure and
/// nothing is downloaded that was not asked for.
///
/// The asset is named for the calling package, which is what lets the bindings
/// tell which providers are installed: they declare one entry point per
/// provider, and only the installed ones resolve.
Future<void> installProvider(List<String> args, OrtProvider provider) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;

    final code = input.config.code;
    final target = targetId(
      os: code.targetOS,
      architecture: code.targetArchitecture,
      iosSdk: code.targetOS == OS.iOS ? code.iOS.targetSdk : null,
    );

    final build = _build(input, provider, target);
    final available = provider.targetsFor(build);
    if (!available.contains(target)) {
      throw StateError(
        '${input.packageName}: there is no ${provider.name}'
        '${build == null ? '' : ' $build'} provider for $target. It is '
        'published for ${available.join(', ')}. Depend on it only for the '
        'platforms that have it, or choose another build.',
      );
    }

    final library = await _resolveProvider(
      input,
      provider,
      target,
      code.targetOS,
      build,
    );
    if (library == null) return;

    output.assets.code.add(
      CodeAsset(
        package: input.packageName,
        name: 'provider',
        linkMode: DynamicLoadingBundled(),
        file: library.uri,
      ),
    );
  });
}

/// Which library to install, from user-defines. The default is the one almost
/// every application wants.
OrtVariant _variant(BuildInput input) {
  final name = input.userDefines['variant'];
  if (name == null) return OrtVariant.base;
  if (name is! String) {
    throw StateError(
      '${input.packageName}: variant must be a string, got '
      '${name.runtimeType}. For example: variant: full',
    );
  }
  return OrtVariant.byName(name);
}

/// Which build of [provider] to install, from user-defines.
///
/// Providers with one build ignore this. CUDA has two, differing in the driver
/// they need rather than in what they do, so the application chooses:
///
/// ```yaml
/// hooks:
///   user_defines:
///     onnxruntime_ep_cuda:
///       build: cuda13
/// ```
String? _build(BuildInput input, OrtProvider provider, String target) {
  if (provider.builds.isEmpty) return null;

  final requested = input.userDefines['build'];
  if (requested == null) return provider.buildFor(target);
  if (requested is! String || !provider.builds.contains(requested)) {
    throw StateError(
      '${input.packageName}: build must be one of '
      '${provider.builds.join(', ')}, got "$requested".',
    );
  }
  return requested;
}

/// Finds a provider library the same way the runtime is found.
/// Installs the onnxruntime-extensions operator library for this target.
///
/// Not a provider: it gives ONNX Runtime operators it does not have rather
/// than somewhere to run the ones it does, and it loads through
/// `RegisterCustomOpsLibrary_V2`. Same shape of work, so the same downloading,
/// caching and local_build override apply.
Future<void> installExtensions(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;

    final code = input.config.code;
    final target = targetId(
      os: code.targetOS,
      architecture: code.targetArchitecture,
      iosSdk: code.targetOS == OS.iOS ? code.iOS.targetSdk : null,
    );

    if (!OrtExtensions.isAvailableOn(target)) {
      throw StateError(
        '${input.packageName}: there is no extensions library for $target. '
        'It is published for ${OrtExtensions.targets.join(', ')}.',
      );
    }

    final library = await _resolveExtensions(input, target, code.targetOS);
    if (library == null) return;

    output.assets.code.add(
      CodeAsset(
        package: input.packageName,
        name: 'extensions',
        linkMode: DynamicLoadingBundled(),
        file: library.uri,
      ),
    );
  });
}

/// Declares the ONNX Runtime GenAI library for the target being built.
///
/// Shaped like [installExtensions] rather than [installProvider], because GenAI
/// is not something ONNX Runtime loads. It is a library an application links to
/// that drives a session itself, so it is installed as an asset of its own and
/// the runtime has to be there beside it.
Future<void> installGenAi(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;

    final code = input.config.code;
    final target = targetId(
      os: code.targetOS,
      architecture: code.targetArchitecture,
      iosSdk: code.targetOS == OS.iOS ? code.iOS.targetSdk : null,
    );

    if (!OrtGenAi.isAvailableOn(target)) {
      throw StateError(
        '${input.packageName}: there is no GenAI library for $target. '
        'Upstream publishes it for ${OrtGenAi.targets.join(', ')}.',
      );
    }

    final library = await _resolveGenAi(input, target, code.targetOS);
    if (library == null) return;

    output.assets.code.add(
      CodeAsset(
        package: input.packageName,
        name: 'genai',
        linkMode: DynamicLoadingBundled(),
        file: library.uri,
      ),
    );
  });
}

Future<File?> _resolveGenAi(
  BuildInput input,
  String target,
  OS os,
) async {
  final fileName = OrtGenAi.fileName(os);

  final override = input.userDefines.path('local_build');
  if (override != null) {
    final file = File.fromUri(_asDirectory(override).resolve(fileName));
    if (file.existsSync()) return file;
    stderr.writeln(
      '${input.packageName}: local_build holds no $fileName, so the '
      'GenAI library is not installed.',
    );
    return null;
  }

  final tag = releaseTag(input, component: 'genai');
  final cached = File.fromUri(
    input.outputDirectoryShared.resolve('$tag/$target/$fileName'),
  );
  if (cached.existsSync()) return cached;

  return _download(
    url: genAiAssetUrl(releaseTag: tag, targetId: target),
    into: cached,
    fileName: fileName,
    target: target,
    package: input.packageName,
  );
}

Future<File?> _resolveExtensions(
  BuildInput input,
  String target,
  OS os,
) async {
  final fileName = OrtExtensions.fileName(os);

  final override = input.userDefines.path('local_build');
  if (override != null) {
    final file = File.fromUri(_asDirectory(override).resolve(fileName));
    if (file.existsSync()) return file;
    stderr.writeln(
      '${input.packageName}: local_build holds no $fileName, so the '
      'extensions library is not installed.',
    );
    return null;
  }

  final tag = releaseTag(input, component: 'extensions');
  final cached = File.fromUri(
    input.outputDirectoryShared.resolve('$tag/$target/$fileName'),
  );
  if (cached.existsSync()) return cached;

  return _download(
    url: extensionsAssetUrl(releaseTag: tag, targetId: target),
    into: cached,
    fileName: fileName,
    target: target,
    package: input.packageName,
  );
}

Future<File?> _resolveProvider(
  BuildInput input,
  OrtProvider provider,
  String target,
  OS os,
  String? build,
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

  final tag = releaseTag(input, component: 'ep-${provider.name}');
  final cached = File.fromUri(
    input.outputDirectoryShared
        .resolve('$tag/${build ?? 'default'}/$target/$fileName'),
  );
  if (cached.existsSync()) return cached;

  return _download(
    url: providerAssetUrl(
      releaseTag: tag,
      provider: provider.name,
      targetId: target,
      build: build,
    ),
    into: cached,
    fileName: fileName,
    target: target,
    package: input.packageName,
  );
}

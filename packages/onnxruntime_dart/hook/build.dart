// Resolves the ONNX Runtime shared library for the target being built and hands
// it to Dart as a code asset, so consumers never fetch or place binaries
// themselves.
//
// Resolution order:
//
//   1. A path given through user-defines, for developing against a local build.
//   2. A previously downloaded copy in the shared output directory.
//   3. The release asset for this target, verified against a pinned SHA-256.
//
// Hooks run in a semi-hermetic environment. Proxy variables are among the few
// passed through, so downloading works behind one.

import 'dart:io';
import 'dart:typed_data';

import 'package:code_assets/code_assets.dart';
import 'package:crypto/crypto.dart';
import 'package:hooks/hooks.dart';
import 'package:onnxruntime_dart/src/hook/release.g.dart';
import 'package:onnxruntime_dart/src/hook/target.dart';

/// Forms the asset id `package:onnxruntime_dart/onnxruntime`.
const _assetName = 'onnxruntime';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;

    final code = input.config.code;
    final target = targetId(
      os: code.targetOS,
      architecture: code.targetArchitecture,
      iosSdk: code.targetOS == OS.iOS ? code.iOS.targetSdk : null,
    );

    final library = await _resolveLibrary(input, target, code.targetOS);
    if (library == null) return;

    output.assets.code.add(
      CodeAsset(
        package: input.packageName,
        name: _assetName,
        linkMode: DynamicLoadingBundled(),
        file: library.uri,
      ),
    );
  });
}

/// Returns the library for [target], or null when none is available yet.
///
/// Returning null leaves the asset undeclared, so anything calling into the
/// runtime fails at load with a missing-asset error. That is deliberate while no
/// release exists: the package's own pure-Dart tests must still run, and a hook
/// that hard-fails would block `dart test` and `dart analyze` outright. Once
/// [releaseTag] is set this branch is unreachable and every failure is loud.
Future<File?> _resolveLibrary(BuildInput input, String target, OS os) async {
  final fileName = libraryFileName(os);

  final override = input.userDefines.path('local_build');
  if (override != null) {
    final file = File.fromUri(_asDirectory(override).resolve(fileName));
    if (!file.existsSync()) {
      throw StateError(
        'onnxruntime_dart: local_build points at $override, which holds no '
        '$fileName. Expected a directory containing the shared library.',
      );
    }
    return file;
  }

  final cached = File.fromUri(
    input.outputDirectoryShared.resolve('$target/$fileName'),
  );
  if (cached.existsSync()) return cached;

  if (releaseTag.isEmpty) {
    stderr.writeln(
      'onnxruntime_dart: no binaries are published yet and no local build was '
      'configured, so no native library is bundled. Set one to use the '
      'runtime:\n'
      '\n'
      '  # pubspec.yaml\n'
      '  hooks:\n'
      '    user_defines:\n'
      '      onnxruntime_dart:\n'
      '        local_build: path/to/directory/containing/$fileName\n',
    );
    return null;
  }

  final expected = assetSha256[target];
  if (expected == null) {
    throw StateError(
      'onnxruntime_dart release $releaseTag publishes no asset for $target. '
      'That is a packaging bug, not a configuration error.',
    );
  }

  return _download(
    url: assetUrl(releaseTag: releaseTag, targetId: target),
    expectedSha256: expected,
    into: cached,
    fileName: fileName,
  );
}

Future<File> _download({
  required Uri url,
  required String expectedSha256,
  required File into,
  required String fileName,
}) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
  final Uint8List archive;
  try {
    final response = await (await client.getUrl(url)).close();
    if (response.statusCode != HttpStatus.ok) {
      throw StateError(
        'onnxruntime_dart could not download $url: HTTP ${response.statusCode}',
      );
    }
    final builder = BytesBuilder(copy: false);
    await response.forEach(builder.add);
    archive = builder.takeBytes();
  } on IOException catch (e) {
    throw StateError('onnxruntime_dart could not download $url: $e');
  } finally {
    client.close(force: true);
  }

  final actual = sha256.convert(archive).toString();
  if (actual != expectedSha256) {
    throw StateError(
      'onnxruntime_dart: $url hashes to $actual but the manifest pins '
      '$expectedSha256. Refusing to use it.',
    );
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
      throw StateError('onnxruntime_dart: truncated archive at entry $name');
    }
    if (name.split('/').last == fileName) {
      return Uint8List.fromList(
        Uint8List.sublistView(tar, offset, offset + size),
      );
    }
    offset += (size + blockSize - 1) & ~(blockSize - 1);
  }
  throw StateError('onnxruntime_dart: archive holds no $fileName');
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
  return String.fromCharCodes(Uint8List.sublistView(header, start, end)).trim();
}

// Generates the Dart wrappers over the ONNX Runtime C API.
//
// Two inputs, each authoritative for what it knows. The header gives names,
// parameter direction and ownership, so the wrappers cannot drift from the
// library they call. The ffigen bindings give the exact FFI types, so the
// emitted calls cannot disagree with the struct they go through.
//
// Anything the mapper does not understand is left out and reported in
// unmapped.txt, rather than guessed at.
//
//   dart run tool/generate_bindings.dart

import 'dart:io';

import 'src/generate.dart';
import 'src/paths.dart';

const _outputDirectory = 'lib/src/bindings/api';

void main() {
  final generated = generate(
    header: File(ortHeader),
    bindings: File(ortBindings),
  );

  // Delete only what this tool produces. The directory also holds hand-written
  // support code, and wiping it wholesale once destroyed that.
  final directory = Directory(_outputDirectory)..createSync(recursive: true);
  for (final stale in directory.listSync().whereType<File>()) {
    if (stale.path.endsWith('.g.dart')) stale.deleteSync();
  }

  for (final entry in generated.files.entries) {
    File('$_outputDirectory/${entry.key}').writeAsStringSync(entry.value);
  }

  final files = generated.files.keys.where((f) => f.endsWith('.g.dart'));
  stdout.writeln(
    'generated ${generated.wrappers} wrappers in ${files.length} files',
  );
  for (final file in files) {
    stdout.writeln('  $file');
  }
  stdout.writeln(
    'skipped ${generated.skipped.length}, listed in unmapped.txt',
  );
}

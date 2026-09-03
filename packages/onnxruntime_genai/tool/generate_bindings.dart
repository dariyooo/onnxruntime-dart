// Generates the Dart wrappers over the ONNX Runtime GenAI C API.
//
// The header is authoritative for names, parameter direction and ownership.
// The ffigen bindings beside it are authoritative for the FFI types. Anything
// this does not understand is left out and written to unmapped.txt rather than
// guessed at, which is the same rule the base package's generator follows.
//
//   dart run tool/generate_bindings.dart

import 'dart:io';

import 'package:dart_style/dart_style.dart';
import 'package:pub_semver/pub_semver.dart';

import 'src/c_api.dart';
import 'src/emit.dart';

const _header = '../../third_party/onnxruntime-genai/src/ort_genai_c.h';
const _outputDirectory = 'lib/src/api';

/// Formatted here rather than left to whoever runs the formatter next. What
/// this writes has to match what a fresh run writes, and CI checks exactly
/// that, so the output is final when it lands.
final _formatter = DartFormatter(languageVersion: Version(3, 6, 0));

void main() {
  final functions = readCApi(File(_header));
  final generated = emit(functions);

  // Only what this tool produces. The directory also holds support.dart, which
  // is hand written, and wiping the directory wholesale would take it.
  final directory = Directory(_outputDirectory)..createSync(recursive: true);
  for (final stale in directory.listSync().whereType<File>()) {
    if (stale.path.endsWith('.g.dart')) stale.deleteSync();
  }

  for (final entry in generated.files.entries) {
    final file = File('$_outputDirectory/${entry.key}');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(_formatter.format(entry.value));
  }

  File('$_outputDirectory/unmapped.txt').writeAsStringSync(
    '${generated.skipped.length} of ${functions.length} functions are not '
    'wrapped.\n\n${generated.skipped.join('\n')}\n',
  );

  stdout.writeln(
    'generated ${generated.wrappers} wrappers in '
    '${generated.files.length} files',
  );
  stdout.writeln(
    'skipped ${generated.skipped.length}, listed in '
    '$_outputDirectory/unmapped.txt',
  );
}

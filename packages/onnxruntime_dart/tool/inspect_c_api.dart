// Reports what the header parser extracts, so its coverage can be judged before
// anything is generated from it.

import 'dart:io';

import 'src/c_api.dart';

void main(List<String> args) {
  final header = File(
    '../../third_party/onnxruntime/include/onnxruntime/core/session/'
    'onnxruntime_c_api.h',
  ).readAsStringSync();

  final declared =
      RegExp(r'ORT_API2_STATUS\(\s*(\w+)').allMatches(header).length;
  final parsed = parseOrtApi(header);
  stdout.writeln('declared: $declared   parsed: ${parsed.length}');

  final byOutputs = <int, int>{};
  for (final f in parsed) {
    byOutputs[f.outputs.length] = (byOutputs[f.outputs.length] ?? 0) + 1;
  }
  stdout.writeln('\nout-parameters per function:');
  for (final e in byOutputs.entries.toList()..sort((a, b) => a.key - b.key)) {
    stdout.writeln('  ${e.key} -> ${e.value} functions');
  }

  stdout.writeln('\ndistinct C types across all parameters:');
  final types = <String, int>{};
  for (final f in parsed) {
    for (final p in f.parameters) {
      types[p.type] = (types[p.type] ?? 0) + 1;
    }
  }
  final sorted = types.entries.toList()..sort((a, b) => b.value - a.value);
  for (final e in sorted.take(18)) {
    stdout.writeln('  ${e.value.toString().padLeft(4)}  ${e.key}');
  }
  stdout.writeln('  ... ${sorted.length} distinct types in total');

  if (args.contains('--show')) {
    for (final name in ['SessionGetInputName', 'GetDimensions', 'Run']) {
      final f = parsed.where((f) => f.name == name).firstOrNull;
      stdout.writeln('\n$name:\n  ${f?.parameters.join('\n  ')}');
    }
  }
}

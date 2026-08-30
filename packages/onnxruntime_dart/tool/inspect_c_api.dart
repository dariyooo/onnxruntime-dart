// Reports how much of the C API the generator can map, and what it cannot.
//
// Coverage is a number rather than a hope: anything unmapped is listed with the
// C type that defeated it, so extending the mapper is a matter of reading this
// output rather than guessing.

import 'dart:io';

import 'src/c_api.dart';
import 'src/types.dart';

const _header =
    '../../third_party/onnxruntime/include/onnxruntime/core/session/'
    'onnxruntime_c_api.h';

/// Groups that a Dart consumer does not call, so their coverage does not count.
const _authoring = {
  'custom op and kernel authoring':
      r'Kernel|CustomOp|ShapeInfer|^Op[A-Z]|OpAttr',
  'execution provider authoring': r'^Ep|EpFactory|EpGraph|NodeCompute|EpDevice',
  'graph and model editing':
      r'Graph|^Node|ValueInfo|ModelEditor|Compile|^Model',
  'training': r'Training|Lora|Adapter',
  'sparse, dlpack, tuning': r'Sparse|DLPack|TuningResult',
};

bool _isAuthoring(String name) =>
    _authoring.values.any((p) => RegExp(p).hasMatch(name));

void main() {
  final apis = parseApis(File(_header).readAsStringSync());
  final functions = [for (final api in apis.values) ...api];
  final consumer =
      functions.where((CFunction f) => !_isAuthoring(f.name)).toList();
  final mapped = consumer.where(isFullyMapped).toList();

  stdout
    ..writeln('parsed        ${functions.length} in ${apis.length} API structs')
    ..writeln('consumer      ${consumer.length}')
    ..writeln(
      'generatable   ${mapped.length}  '
      '(${(100 * mapped.length / consumer.length).round()}%)',
    )
    ..writeln();

  final blockers = <String, int>{};
  for (final f in consumer.where((CFunction f) => !isFullyMapped(f))) {
    for (final reason in unmappedReasons(f).toSet()) {
      blockers[reason] = (blockers[reason] ?? 0) + 1;
    }
  }
  stdout.writeln('what blocks the rest, most common first:');
  final sorted = blockers.entries.toList()..sort((a, b) => b.value - a.value);
  for (final e in sorted.take(14)) {
    stdout.writeln('  ${e.value.toString().padLeft(3)}  ${e.key}');
  }
  stdout.writeln('  ${sorted.length} distinct blockers');
}

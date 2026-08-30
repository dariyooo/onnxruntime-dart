// Load a model, run it, read the result.
//
//   dart run example/onnxruntime_dart_example.dart path/to/model.onnx

import 'dart:io';
import 'dart:typed_data';

import 'package:onnxruntime_dart/onnxruntime_dart.dart';

void main(List<String> arguments) {
  if (arguments.length != 1) {
    stderr.writeln('usage: onnxruntime_dart_example.dart <model.onnx>');
    exit(64);
  }

  stdout.writeln('ONNX Runtime ${runtimeVersion()}');

  final session = Session.fromBytes(File(arguments.single).readAsBytesSync());
  try {
    for (final input in session.inputs) {
      stdout.writeln('in   $input');
    }
    for (final output in session.outputs) {
      stdout.writeln('out  $output');
    }

    // Zeros of the right shape, which is enough to show the mechanics. A real
    // caller puts its own data here.
    final meta = session.inputs.single;
    final shape = [for (final d in meta.shape) d < 0 ? 1 : d];
    final count = shape.fold(1, (a, b) => a * b);

    final tensor = OrtTensor.fromData(
      OrtElementType.float32,
      Float32List(count),
      shape,
    );
    try {
      final results = session.run({meta.name: tensor});
      for (final entry in results.entries) {
        stdout.writeln('${entry.key} ${entry.value.view.shape}');
        entry.value.release();
      }
    } finally {
      tensor.release();
    }
  } finally {
    session.release();
  }
}

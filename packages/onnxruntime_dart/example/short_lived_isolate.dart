// Run one inference off the calling thread and let the isolate go.
//
// This is the Dart equivalent of Flutter's compute(): Isolate.run spawns an
// isolate, runs the closure, returns the result and tears the isolate down.
//
// Right for a one-off. Wrong in a loop, because building a session runs graph
// optimisation and that cost is paid again on every call. See
// long_lived_isolate.dart for the shape that keeps one.
//
//   dart run example/short_lived_isolate.dart <model.onnx>

import 'dart:io';
import 'dart:isolate';

import 'package:onnxruntime_dart/onnxruntime_dart.dart';

Future<void> main(List<String> args) async {
  final model = await File(args.single).readAsBytes();

  // The model bytes are copied into the isolate. TransferableTypedData hands
  // ownership over instead, which matters once models get large.
  final description = await Isolate.run(() {
    final session = Session.fromBytes(model);
    try {
      return session.inputs.map((i) => '${i.name} ${i.shape}').join(', ');
    } finally {
      session.dispose();
    }
  });

  stdout.writeln('inputs: $description');
}

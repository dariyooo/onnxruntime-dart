// Two ways to keep inference off the main isolate.
//
// Neither is built into the package: a session belongs to the isolate that
// created it, and which of these fits depends on how often you infer.
//
//   dart run example/isolates.dart path/to/model.onnx

import 'dart:isolate';
import 'dart:typed_data';

import 'package:onnxruntime_dart/onnxruntime_dart.dart';

/// One-off work, on an isolate that exists for the length of the call.
///
/// Simple, and wrong for anything repeated: loading runs the graph
/// optimisation passes, so this pays for them every time.
Future<Float32List> once(Uint8List model, Float32List input, List<int> shape) =>
    Isolate.run(() {
      final session = Session.fromBytes(model);
      try {
        return _run(session, input, shape);
      } finally {
        session.release();
      }
    });

/// A worker that loads once and answers many requests.
///
/// This is what production looks like. The session outlives each request, so
/// the optimisation passes are paid for once.
final class InferenceWorker {
  InferenceWorker._(this._commands, this._responses, this._isolate);

  /// Starts a worker holding [model].
  static Future<InferenceWorker> start(Uint8List model) async {
    final responses = ReceivePort();
    final isolate = await Isolate.spawn(
      _serve,
      (model: model, reply: responses.sendPort),
    );

    final events = responses.asBroadcastStream();
    final commands = await events.first as SendPort;
    return InferenceWorker._(commands, events, isolate);
  }

  final SendPort _commands;
  final Stream<dynamic> _responses;
  final Isolate _isolate;

  /// Runs the model, one request at a time.
  Future<Float32List> infer(Float32List input, List<int> shape) {
    _commands.send((input: input, shape: shape));
    return _responses
        .firstWhere((r) => r is Float32List)
        .then((r) => r as Float32List);
  }

  /// Stops the worker and frees its session.
  void close() => _isolate.kill();

  static void _serve(({Uint8List model, SendPort reply}) start) {
    final commands = ReceivePort();
    start.reply.send(commands.sendPort);

    // Loaded once, outside the request loop. That is the whole point.
    final session = Session.fromBytes(start.model);
    commands.listen((message) {
      final request = message as ({Float32List input, List<int> shape});
      start.reply.send(_run(session, request.input, request.shape));
    });
  }
}

/// Runs one inference and copies the result out.
///
/// Copied because the view borrows the tensor's own memory, which is freed
/// before the caller sees it.
Float32List _run(Session session, Float32List input, List<int> shape) {
  final tensor = OrtTensor.fromData(OrtElementType.float32, input, shape);
  try {
    final results = session.run({session.inputs.single.name: tensor});
    final output = results.values.single;
    try {
      return Float32List.fromList(
        Uint8List.fromList(output.view.data).buffer.asFloat32List(),
      );
    } finally {
      output.release();
    }
  } finally {
    tensor.release();
  }
}

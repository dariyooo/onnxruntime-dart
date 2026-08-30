// Keep one isolate and one session, and serve many requests over a port.
//
// The right shape whenever inference happens more than once. Building a session
// runs graph optimisation, so it is built once inside the worker and reused,
// rather than rebuilt per call as Isolate.run would.
//
// It also moves your own pre- and post-processing off the calling thread, which
// awaiting session.run() does not: that moves inference alone.
//
//   dart run example/long_lived_isolate.dart <model.onnx>

import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:onnxruntime_dart/onnxruntime_dart.dart';

/// Owns a session on its own isolate for as long as you keep it.
class InferenceWorker {
  InferenceWorker._(this._commands, this._responses, this._isolate);

  final SendPort _commands;
  final ReceivePort _responses;
  final Isolate _isolate;

  final _pending = <int, Completer<Object?>>{};
  var _nextId = 0;

  static Future<InferenceWorker> spawn(List<int> model) async {
    final responses = ReceivePort();
    final ready = Completer<SendPort>();

    final subscription = responses.listen(null);
    subscription.onData((message) {
      ready.complete(message as SendPort);
      subscription.onData(null);
    });

    final isolate = await Isolate.spawn(_run, (responses.sendPort, model));
    final worker = InferenceWorker._(await ready.future, responses, isolate);
    subscription.onData(worker._onResponse);
    return worker;
  }

  /// Asks the worker to describe the model. Stands in for a real request.
  Future<Object?> describe() {
    final id = _nextId++;
    final completer = Completer<Object?>();
    _pending[id] = completer;
    _commands.send(id);
    return completer.future;
  }

  void _onResponse(dynamic message) {
    final (int id, Object? result) = message as (int, Object?);
    _pending.remove(id)!.complete(result);
  }

  /// Tears down the worker. The session goes with it.
  void close() {
    _isolate.kill(priority: Isolate.immediate);
    _responses.close();
  }

  /// Runs on the worker isolate. The session is built once, here, and every
  /// request reuses it.
  static void _run((SendPort, List<int>) setup) {
    final (responses, model) = setup;
    final commands = ReceivePort();
    responses.send(commands.sendPort);

    final session = Session.fromBytes(model);
    commands.listen((message) {
      final id = message as int;
      responses.send((id, session.inputs.map((i) => i.name).toList()));
    });
  }
}

Future<void> main(List<String> args) async {
  final model = await File(args.single).readAsBytes();
  final worker = await InferenceWorker.spawn(model);

  // Many requests, one session.
  for (var i = 0; i < 3; i++) {
    stdout.writeln('request $i: ${await worker.describe()}');
  }

  worker.close();
}

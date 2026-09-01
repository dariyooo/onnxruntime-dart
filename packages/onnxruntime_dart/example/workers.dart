// Two ways to keep inference off the page, the web counterpart of
// example/isolates.dart.
//
// Neither is built into the package: a session belongs to the thread that
// created it, and a browser has no isolates, so a worker is the only way to
// run a model without freezing the page. Which of these fits depends on how
// often you infer.
//
// This is the page half. The worker half is example/worker_body.dart, and it
// is a program of its own because a worker needs a script rather than a
// closure:
//
//   dart compile js example/worker_body.dart -o web/worker_body.dart.js

import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// One-off work, on a worker that exists for the length of the call.
///
/// Simple, and wrong for anything repeated: it pays to fetch and instantiate
/// the runtime, then to load the model, every single time.
Future<Float32List> once(
  String workerScript,
  String loaderUrl,
  Uint8List wasm,
  Uint8List model,
  Float32List input,
  List<int> shape,
) async {
  final worker = web.Worker(workerScript.toJS);
  final answer = Completer<Float32List>();

  worker.onmessage = ((web.MessageEvent event) {
    answer.complete((event.data as JSFloat32Array).toDart);
  }).toJS;

  worker.postMessage({
    'loader': loaderUrl,
    'wasm': wasm.toJS,
    'model': model.toJS,
    'input': input.toJS,
    'shape': shape.jsify(),
  }.jsify());

  return answer.future.whenComplete(() => worker.terminate());
}

/// A worker that loads once and answers many requests.
///
/// This is what production looks like. The runtime is instantiated and the
/// model loaded once, so neither is paid for per request.
final class InferenceWorker {
  InferenceWorker._(this._worker);

  /// Starts a worker holding [model], ready to answer requests.
  static Future<InferenceWorker> start({
    required String workerScript,
    required String loaderUrl,
    required Uint8List wasm,
    required Uint8List model,
  }) async {
    final worker = web.Worker(workerScript.toJS);
    final ready = Completer<void>();

    worker.onmessage = ((web.MessageEvent event) => ready.complete()).toJS;
    worker.postMessage({
      'loader': loaderUrl,
      'wasm': wasm.toJS,
      'model': model.toJS,
    }.jsify());

    await ready.future;
    return InferenceWorker._(worker);
  }

  final web.Worker _worker;

  /// Runs the model, one request at a time.
  Future<Float32List> infer(Float32List input, List<int> shape) {
    final answer = Completer<Float32List>();
    _worker.onmessage = ((web.MessageEvent event) {
      answer.complete((event.data as JSFloat32Array).toDart);
    }).toJS;

    _worker.postMessage({
      'input': input.toJS,
      'shape': shape.jsify(),
    }.jsify());
    return answer.future;
  }

  /// Stops the worker and frees its session.
  void close() => _worker.terminate();
}

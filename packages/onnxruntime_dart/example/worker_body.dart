// The worker half of example/workers.dart.
//
// A program of its own, because a worker runs a script rather than a closure.
// Compile it next to your page and pass the result to `Worker`:
//
//   dart compile js example/worker_body.dart -o web/worker_body.dart.js
//
// It serves both shapes in example/workers.dart. The first message carries the
// runtime and the model; if it also carries an input, this answers once and
// the page throws the worker away. Otherwise it replies when it is ready and
// then answers each request against the session it already holds.

import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:onnxruntime_dart/onnxruntime_dart.dart';

@JS('self')
external _WorkerScope get _self;

extension type _WorkerScope(JSObject _) implements JSObject {
  external set onmessage(JSFunction value);
  external void postMessage(JSAny? message);
}

extension type _Message(JSObject _) implements JSObject {
  external JSObject get data;
}

extension type _Start(JSObject _) implements JSObject {
  external String get loader;
  external JSUint8Array get wasm;
  external JSUint8Array get model;
  external JSFloat32Array? get input;
  external JSArray<JSNumber>? get shape;
}

extension type _Request(JSObject _) implements JSObject {
  external JSFloat32Array get input;
  external JSArray<JSNumber> get shape;
}

void main() {
  // Sync, because a callback that crosses into JavaScript cannot return a
  // future. Each reply is posted when its work finishes instead.
  _self.onmessage = ((_Message event) => unawaited(_start(event))).toJS;
}

Future<void> _start(_Message event) async {
  final start = _Start(event.data);

  // The bytes rather than a URL: the page has already fetched the runtime, and
  // a worker resolves a relative URL against its own script, not the page.
  await openOnnxRuntime(
    web: WebRuntimeOptions(start.loader, wasmBytes: start.wasm.toDart),
  );

  // `load` rather than `fromBytes`, so this works on the plain build and on
  // the WebGPU one, which can suspend while the GPU is set up.
  final session = await Session.load(start.model.toDart);

  final input = start.input;
  if (input != null) {
    // The one-off shape: answer and be thrown away.
    final shape = [for (final n in start.shape!.toDart) n.toDartInt];
    _self.postMessage((await _run(session, input.toDart, shape)).toJS);
    session.release();
    return;
  }

  // The long-lived shape: say the session is ready, then serve requests
  // against it. Loading is what this shape exists to do only once.
  _self.onmessage = ((_Message event) {
    final request = _Request(event.data);
    unawaited(
      _run(
        session,
        request.input.toDart,
        [for (final n in request.shape.toDart) n.toDartInt],
      ).then((output) => _self.postMessage(output.toJS)),
    );
  }).toJS;
  _self.postMessage(null);
}

/// Runs one inference and copies the result out.
///
/// Copied because the view borrows the tensor's own heap, which is freed
/// before the page sees it.
Future<Float32List> _run(
  Session session,
  Float32List input,
  List<int> shape,
) async {
  final tensor = OrtTensor.fromData(OrtElementType.float32, input, shape);
  try {
    final results =
        await session.runAsync({session.inputs.single.name: tensor});
    final output = results.values.single;
    try {
      return Float32List.fromList(output.view.float32s);
    } finally {
      output.release();
    }
  } finally {
    tensor.release();
  }
}

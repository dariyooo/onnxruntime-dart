/// The body of the worker that `worker_test.dart` spawns.
///
/// Compiled separately, because a worker needs its own script: the test bundle
/// has the test runner as its entry point and cannot be re-entered here. The
/// test compiles this next to itself and spawns the result.
///
/// The counterpart of the top-level function `isolate_test.dart` hands to
/// `Isolate.run`. Nothing is shared with the page: a session and its tensors
/// belong to the thread that made them, so what crosses back is plain data.
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:onnxruntime_dart/onnxruntime_dart.dart';

import 'embedded_model.dart';

@JS('self')
external _WorkerScope get _self;

extension type _WorkerScope(JSObject _) implements JSObject {
  external set onmessage(JSFunction value);
  external void postMessage(JSAny? message);
}

extension type _Message(JSObject _) implements JSObject {
  external JSObject get data;
}

/// What the page sends: where the runtime is, and its bytes.
///
/// Absolute, and the bytes already fetched. A worker resolves a relative URL
/// against its own script rather than the page, so handing it the page's
/// relative path would look for the runtime in the wrong directory.
extension type _Work(JSObject _) implements JSObject {
  external String get loader;
  external JSUint8Array get wasm;
}

void main() {
  // Sync, because a callback that crosses into JavaScript cannot return a
  // future. The reply is posted when the work finishes instead.
  _self.onmessage = ((_Message event) => unawaited(_run(event))).toJS;
}

Future<void> _run(_Message event) async {
  try {
    final work = _Work(event.data);
    await openOnnxRuntime(
      web: WebRuntimeOptions(work.loader, wasmBytes: work.wasm.toDart),
    );

    // The asynchronous form, so this is the same code whichever build the
    // page handed over.
    final session = await Session.load(absModel());
    try {
      final input = OrtTensor.fromData(
        OrtElementType.float32,
        Float32List.fromList([-1, 2, -3, 4, -5, 6, -7, 8, -9, 10]),
        [1, 2, 5],
      );
      try {
        final outputs =
            await session.runAsync({session.inputs.single.name: input});
        final output = outputs.values.single;
        try {
          // Copied, not viewed: the view borrows heap this function frees.
          _self.postMessage(
            Float32List.fromList(output.view.float32s).toJS,
          );
        } finally {
          output.release();
        }
      } finally {
        input.release();
      }
    } finally {
      session.release();
    }
  } catch (error) {
    _self.postMessage('error: $error'.toJS);
  }
}

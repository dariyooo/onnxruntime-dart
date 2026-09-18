@TestOn('browser')
@Tags(['exclusive'])

/// Running a model in a spawned worker.
///
/// The web counterpart of `isolate_test.dart`, and it exists for the same
/// reason. The package ships no worker and no sendable session: a session
/// belongs to the thread that created it. What is owed is proof that creating
/// one somewhere else works and gives the same answer, since a browser has no
/// isolates and a worker is the only way to keep a model off the page.
///
/// The interesting part is not the message passing. It is that the runtime
/// spawns its own pthread workers, so this is a worker spawning workers, and
/// that the shared heap survives being set up off the main thread.
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:web/web.dart' as web;

import 'src/web_runtime_config.dart';

/// Where the compiled worker body is served, relative to the test page.
const _workerScript = 'src/worker_entry.dart.js';

/// The answer the model gives for the input the worker feeds it.
const _expected = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];

String _absolute(String url) => web.URL(url, web.window.location.href).href;

Future<bool> _served(String url) async {
  final response = await web.window.fetch(url.toJS).toDart;
  return response.ok;
}

Future<Uint8List> _bytes(String url) async {
  final response = await web.window.fetch(url.toJS).toDart;
  if (!response.ok) {
    throw StateError('could not fetch $url: HTTP ${response.status}');
  }
  return (await response.arrayBuffer().toDart).toDart.asUint8List();
}

/// Starts a worker and completes with whatever it posts back.
Future<Object?> _runInWorker(String loader, Uint8List wasm) {
  final worker = web.Worker(_absolute(_workerScript).toJS);
  final answer = Completer<Object?>();

  worker.onmessage = ((web.MessageEvent event) {
    if (answer.isCompleted) return;
    // A string is the worker reporting a failure, anything else is the
    // output. Kept apart here so a failure arrives as a readable message
    // rather than a cast error.
    final data = event.data;
    answer.complete(data.isA<JSString>()
        ? (data as JSString).toDart
        : (data as JSFloat32Array).toDart);
  }).toJS;

  worker.onerror = ((JSObject error) {
    if (!answer.isCompleted) {
      answer.completeError(StateError('the worker failed: $error'));
    }
  }).toJS;

  // The bytes rather than the URL, so the worker does not fetch the runtime a
  // second time, and the absolute loader URL, because a worker resolves a
  // relative one against its own script.
  worker.postMessage({
    'loader': _absolute(webRuntimeLoader),
    'wasm': wasm.toJS,
  }.jsify());

  return answer.future.whenComplete(() => worker.terminate());
}

void main() {
  late String reason;
  late Uint8List wasm;

  setUpAll(() async {
    if (webRuntimeLoader.isEmpty) {
      reason = 'no WebAssembly runtime here; run tool/fetch_web_runtime.sh';
      return;
    }
    if (!await _served(_absolute(_workerScript))) {
      reason = 'the worker body is not compiled; run '
          'tool/fetch_web_runtime.sh, which compiles it';
      return;
    }
    wasm = await _bytes(_absolute(webRuntimeWasm));
    reason = '';
  });

  test('a spawned worker produces the same output as the page', () async {
    if (reason.isNotEmpty) return markTestSkipped(reason);

    final result = await _runInWorker(webRuntimeLoader, wasm);
    expect(result, isA<Float32List>(), reason: 'the worker said: $result');
    expect(result, _expected);
  });

  test('several workers can run at once', () async {
    if (reason.isNotEmpty) return markTestSkipped(reason);

    // Each worker instantiates its own copy of the runtime and its own pthread
    // pool. Starting them together is the interesting case: nothing here is
    // shared, so nothing should serialise or collide.
    final results = await Future.wait([
      for (var i = 0; i < 3; i++) _runInWorker(webRuntimeLoader, wasm),
    ]);

    for (final result in results) {
      expect(result, isA<Float32List>(), reason: 'a worker said: $result');
      expect(result, _expected);
    }
  });
}

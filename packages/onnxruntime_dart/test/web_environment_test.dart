@TestOn('browser')
@Tags(['exclusive'])

/// What the page has to provide for the runtime to be usable.
///
/// One thing here depends on how the page is served rather than on our code,
/// and it fails deep inside an allocation with an assertion about buffer kinds
/// if it is wrong. Checked here instead, where the message can say what to do.
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:onnxruntime_dart/src/backend/wasm/loader.dart';
import 'package:onnxruntime_dart/src/backend/wasm/module.dart';
import 'package:test/test.dart';

import 'src/runtime.dart';

@JS('globalThis')
external JSObject get _global;

void main() {
  setUpAll(ensureRuntime);

  test('the heap is shared, because every runtime we ship is threaded', () {
    // Not a choice made per page: the build is `ort-wasm-simd-threaded`, so
    // its memory is shared whether or not the page can use the threads.
    final buffer = ortModule.heapU8.getProperty<JSObject>('buffer'.toJS);
    final kind = buffer
        .getProperty<JSObject>('constructor'.toJS)
        .getProperty<JSString>('name'.toJS)
        .toDart;

    expect(kind, 'SharedArrayBuffer');
  }, skip: skipWithoutRuntime);

  test('a typed view of the heap can be taken', () {
    // Every call through the arena does this. It is also the whole of the
    // page requirement: a browser hides the `SharedArrayBuffer` constructor
    // unless the page is cross-origin isolated, and a Dart compiler that
    // checks a buffer's kind before viewing it then has nothing to compare
    // against. dart2js never looks, so it works either way; dart2wasm does,
    // and fails an assertion inside the allocation rather than here.
    expect(
      () => Uint32List.view(ortModule.bytes.buffer, 0, 1),
      returnsNormally,
      reason: 'the runtime heap could not be viewed. Serve the page with '
          'COOP and COEP so it is cross-origin isolated, which is what the '
          'runtime needs for threads anyway. globalThis.SharedArrayBuffer is '
          '${_global.has('SharedArrayBuffer') ? 'defined' : 'missing'} and '
          'crossOriginIsolated is '
          '${_global.getProperty<JSBoolean?>('crossOriginIsolated'.toJS)?.toDart}',
    );
  }, skip: skipWithoutRuntime);
}

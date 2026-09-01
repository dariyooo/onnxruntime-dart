/// The five exports Asyncify replaces, seen as what they actually return.
///
/// ONNX Runtime compiles the WebGPU and WebNN builds with `ASYNCIFY=1`, and
/// `Module.asyncInit()` then swaps these five for wrappers. The generated
/// bindings type them as returning a number, which is only half true after
/// that: `pre-async.js` returns the raw result when the call did not suspend
/// and a promise when it did.
///
/// That is why a synchronous backend cannot drive one of those builds. It
/// would work for a model that stays on the CPU and hand back a promise as
/// though it were a handle the moment one touched the GPU, which is worse than
/// refusing.
///
/// So the same exports are declared here returning `JSAny`, and [settle] deals
/// with whichever came back.
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'module.dart';

extension OrtAsyncifyApi on OrtModule {
  /// Installs the wrappers. Calling twice is harmless; the second call is a
  /// no-op upstream.
  @JS('asyncInit')
  external void asyncInit();

  @JS('_OrtCreateSession')
  external JSAny ortCreateSessionMaybeAsync(
      JSNumber data, JSNumber length, JSNumber options);

  @JS('_OrtRun')
  external JSAny ortRunMaybeAsync(
    JSNumber session,
    JSNumber inputNames,
    JSNumber inputs,
    JSNumber inputCount,
    JSNumber outputNames,
    JSNumber outputCount,
    JSNumber outputs,
    JSNumber runOptions,
  );

  @JS('_OrtRunWithBinding')
  external JSAny ortRunWithBindingMaybeAsync(JSNumber session, JSNumber binding,
      JSNumber outputCount, JSNumber outputs, JSNumber runOptions);

  @JS('_OrtBindInput')
  external JSAny ortBindInputMaybeAsync(
      JSNumber binding, JSNumber name, JSNumber tensor);

  @JS('_OrtAppendExecutionProvider')
  external JSAny ortAppendExecutionProviderMaybeAsync(JSNumber options,
      JSNumber name, JSNumber keys, JSNumber values, JSNumber count);
}

/// Whether this module has had Asyncify wrappers installed over it.
///
/// Only those builds define `asyncInit`, so its presence is also how the
/// loader tells the two kinds of build apart.
bool isAsyncifyBuild(OrtModule module) => module.has('asyncInit');

/// The number a wrapped call produced, awaiting it when it suspended.
Future<int> settle(JSAny result) async {
  if (result.isA<JSPromise>()) {
    final value = await (result as JSPromise<JSAny>).toDart;
    return (value as JSNumber).toDartInt;
  }
  return (result as JSNumber).toDartInt;
}

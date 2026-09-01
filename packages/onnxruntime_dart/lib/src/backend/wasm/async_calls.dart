/// The seam on an Asyncify build of the WebAssembly runtime.
///
/// Everything that cannot suspend is inherited from the synchronous backend.
/// The five calls Asyncify wraps are overridden: the asynchronous forms await
/// what comes back, and the synchronous forms refuse rather than reading a
/// promise as a handle.
///
/// This is the only backend that works with the WebGPU and WebNN builds,
/// because reading results back off a GPU is what makes a run suspend.
library;

import 'dart:js_interop';
import 'dart:typed_data';

import '../../annotations.dart';
import '../interface.dart';
import '../types.dart';
import '../wasm_calls.dart';
import 'api.g.dart';
import 'arena.dart';
import 'asyncify.dart';
import 'module.dart';
import 'status.dart';

/// What to tell someone who called a synchronous form here.
const _whySync =
    'this is an Asyncify build, where the call can suspend and hand back a '
    'promise instead of a result. Use the asynchronous form, or serve the '
    'plain onnxruntime_web build, which never suspends';

final class AsyncWasmCalls extends WasmCalls
    implements OrtAsyncCalls, OrtAsyncSessionCalls {
  AsyncWasmCalls(super.module) {
    // Installs the wrappers. Until this runs the exports are the raw ones and
    // a WebGPU run would return before its results were readable.
    module.asyncInit();
  }

  @override
  @NativeOnly(_whySync)
  OrtPtr createSession(Uint8List model, OrtPtr options) =>
      unsupportedOnWeb('createSession', _whySync);

  @override
  Future<OrtPtr> createSessionAsync(Uint8List model, OrtPtr options) async {
    final arena = WasmArena(module);
    try {
      final built = buildOptions(arena, pendingOptions(options));
      try {
        final data = arena.data(model);
        final handle = await settle(
          module.ortCreateSessionMaybeAsync(
            data.toJS,
            model.lengthInBytes.toJS,
            built.toJS,
          ),
        );
        return OrtPtr(checkHandle(module, handle, 'OrtCreateSession'));
      } finally {
        module.ortReleaseSessionOptions(built.toJS);
      }
    } finally {
      arena.releaseAll();
    }
  }

  @override
  @NativeOnly(_whySync)
  List<OrtPtr> run(OrtPtr session, Map<String, OrtPtr> inputs,
          List<String> outputNames, OrtPtr runOptions) =>
      unsupportedOnWeb('run', _whySync);

  @override
  Future<List<OrtPtr>> runAsync(
    OrtPtr session,
    Map<String, OrtPtr> inputs,
    List<String> outputNames,
    OrtPtr runOptions,
  ) async {
    final arena = WasmArena(module);
    try {
      final names = arena.strings(inputs.keys.toList());
      final values =
          arena.handles([for (final value in inputs.values) value.address]);
      final wanted = arena.strings(outputNames);
      final results = arena.slots(outputNames.length);

      final code = await settle(
        module.ortRunMaybeAsync(
          session.address.toJS,
          names.toJS,
          values.toJS,
          inputs.length.toJS,
          wanted.toJS,
          outputNames.length.toJS,
          results.toJS,
          runOptions.address.toJS,
        ),
      );
      check(module, code, 'OrtRun');

      return [
        for (var i = 0; i < outputNames.length; i++)
          OrtPtr(module.readPointer(results + 4 * i)),
      ];
    } finally {
      // Only after the run has completed. Freeing while it is suspended would
      // pull the argument arrays out from under it.
      arena.releaseAll();
    }
  }

  @override
  @NativeOnly(_whySync)
  void runWithBinding(OrtPtr session, OrtPtr binding, OrtPtr runOptions) =>
      unsupportedOnWeb('runWithBinding', _whySync);

  @override
  @NativeOnly(_whySync)
  void bindInput(OrtPtr binding, String name, OrtPtr tensor) =>
      unsupportedOnWeb('bindInput', _whySync);

  @override
  @NativeOnly(_whySync)
  void appendExecutionProvider(
          OrtPtr options, String name, Map<String, String> configuration) =>
      unsupportedOnWeb('appendExecutionProvider', _whySync);
}

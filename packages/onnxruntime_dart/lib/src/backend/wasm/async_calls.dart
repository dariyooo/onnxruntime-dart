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
import 'session_options.dart';
import 'status.dart';
import 'webnn.dart';

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
      final pending = pendingOptions(options);
      final built = buildOptions(arena, pending);
      try {
        // After the options handle exists and before the session reads it.
        await _applyProvidersAsync(arena, built, pending);

        // WebNN takes a context this side has to make. Parked on the module
        // for the provider's constructor to pick up, then handed to the
        // session once it exists.
        final webnn = pending.providers
            .where((provider) => isWebNn(provider.$1))
            .firstOrNull;
        final context =
            webnn == null ? null : await beginWebNnSession(module, webnn.$2);

        var handle = 0;
        try {
          final data = arena.data(model);
          handle = await settle(
            module.ortCreateSessionMaybeAsync(
              data.toJS,
              model.lengthInBytes.toJS,
              built.toJS,
            ),
          );
        } finally {
          // Even when the session failed: a context left behind would be
          // taken by whatever is created next.
          if (webnn != null) endWebNnSession(module, context, handle);
        }
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

  /// Does nothing, because appending a provider here would have to suspend.
  ///
  /// `buildOptions` calls this while it puts the options together, which on
  /// this build is too early: requesting a device is a promise. The providers
  /// are applied by [_applyProvidersAsync] immediately afterwards, from
  /// [createSessionAsync], which can await them.
  @override
  void applyProviders(
    WasmArena arena,
    int handle,
    PendingSessionOptions pending,
  ) {}

  /// Appends the requested providers, awaiting each.
  ///
  /// The reason a WebGPU session has to be created asynchronously: the device
  /// is requested here, and that is a promise.
  Future<void> _applyProvidersAsync(
    WasmArena arena,
    int handle,
    PendingSessionOptions pending,
  ) async {
    for (final (name, configuration) in pending.providers) {
      final code = await settle(
        module.ortAppendExecutionProviderMaybeAsync(
          handle.toJS,
          arena.string(name).toJS,
          arena.strings(configuration.keys.toList()).toJS,
          arena.strings(configuration.values.toList()).toJS,
          configuration.length.toJS,
        ),
      );
      check(module, code, 'OrtAppendExecutionProvider');
    }
  }
}

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

  /// Creates a session synchronously, where nothing has to suspend.
  ///
  /// Setting up an accelerator is what suspends, and that only happens when
  /// one was asked for. Without a provider this is the same work the plain
  /// build does, so it is allowed rather than refused on principle.
  @override
  OrtPtr createSession(Uint8List model, OrtPtr options) {
    final pending = pendingOptions(options);
    if (pending.providers.isNotEmpty) {
      throw UnsupportedError(
        'a session on ${pending.providers.map((p) => p.$1).join(', ')} cannot '
        'be created synchronously: requesting the device is asynchronous. Use '
        'Session.load, which works on every build. Without a provider, '
        'Session.fromBytes works here too.',
      );
    }

    final arena = WasmArena(module);
    var suspended = false;
    try {
      final built = buildOptions(arena, pending);
      try {
        final data = arena.data(model);
        final outcome = module.ortCreateSessionMaybeAsync(
          data.toJS,
          model.lengthInBytes.toJS,
          built.toJS,
        );

        if (outcome.isA<JSPromise>()) {
          suspended = true;
          (outcome as JSPromise<JSAny>).toDart.whenComplete(arena.releaseAll);
          throw UnsupportedError(
            'creating this session suspended even though no provider was '
            'requested. Use Session.load, which can wait for it.',
          );
        }

        return OrtPtr(checkHandle(
          module,
          (outcome as JSNumber).toDartInt,
          'OrtCreateSession',
        ));
      } finally {
        module.ortReleaseSessionOptions(built.toJS);
      }
    } finally {
      if (!suspended) arena.releaseAll();
    }
  }

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

  /// Runs synchronously, which works here as long as nothing suspends.
  ///
  /// Asyncify instruments the whole module but only suspends when a call
  /// reaches something asynchronous, and a session on the CPU never does. So a
  /// model that does not touch an accelerator runs synchronously on this build
  /// exactly as it would on the plain one, and refusing it outright would be
  /// stricter than the runtime is.
  ///
  /// If it does suspend there is no way to wait here, and the run is still
  /// writing into the arena, so the arena is handed to the promise to free
  /// when the run finishes rather than pulled out from under it. That case
  /// throws, because there is no result to return.
  @override
  List<OrtPtr> run(OrtPtr session, Map<String, OrtPtr> inputs,
      List<String> outputNames, OrtPtr runOptions) {
    final arena = WasmArena(module);
    var suspended = false;
    try {
      final names = arena.strings(inputs.keys.toList());
      final values =
          arena.handles([for (final value in inputs.values) value.address]);
      final wanted = arena.strings(outputNames);
      final results = arena.slots(outputNames.length);

      final outcome = module.ortRunMaybeAsync(
        session.address.toJS,
        names.toJS,
        values.toJS,
        inputs.length.toJS,
        wanted.toJS,
        outputNames.length.toJS,
        results.toJS,
        runOptions.address.toJS,
      );

      if (outcome.isA<JSPromise>()) {
        suspended = true;
        // Still running, so its memory is still live. Freed when it finishes.
        (outcome as JSPromise<JSAny>).toDart.whenComplete(arena.releaseAll);
        throw UnsupportedError(
          'this run suspended, which a synchronous call cannot wait for. That '
          'happens when the session is on an accelerator: reading results '
          'back off a GPU is asynchronous. Use runAsync, which works on every '
          'build. The run itself was not cancelled and its memory is released '
          'when it finishes.',
        );
      }

      check(module, (outcome as JSNumber).toDartInt, 'OrtRun');
      return [
        for (var i = 0; i < outputNames.length; i++)
          OrtPtr(module.readPointer(results + 4 * i)),
      ];
    } finally {
      if (!suspended) arena.releaseAll();
    }
  }

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

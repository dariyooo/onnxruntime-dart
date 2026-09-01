/// The seam, on the web.
///
/// Implements the same interface the FFI backend does, over the WebAssembly
/// build's own exports. Those are generated from `onnxruntime/wasm/api.h`, and
/// which C function each operation corresponds to is written down once in
/// `tool/src/seam.dart`.
///
/// Two things differ from native and are handled here rather than above the
/// seam. Session options are buffered until the session is created, because
/// the wasm build takes them all as constructor parameters. And a handle is a
/// heap offset rather than a pointer, so everything crossing into the runtime
/// is copied into that heap and freed after.
library;

import 'dart:js_interop';
import 'dart:typed_data';

import 'package:meta/meta.dart';

import '../annotations.dart';
import 'interface.dart';
import 'types.dart';
import 'wasm/api.g.dart';
import 'wasm/async_calls.dart';
import 'wasm/asyncify.dart';
import 'wasm/arena.dart';
import 'wasm/loader.dart';
import 'wasm/module.dart';
import 'wasm/session_options.dart';
import 'wasm/status.dart';

/// Returns the backend for this platform.
///
/// Two of them. ONNX Runtime compiles the WebGPU and WebNN builds with
/// Asyncify, where a run can suspend and hand back a promise, so those need a
/// backend that awaits. The plain build never suspends and uses the
/// synchronous one. Which is which is decided by the module itself, since only
/// an Asyncify build defines `asyncInit`.
OrtCalls createCalls() => isAsyncifyBuild(ortModule)
    ? AsyncWasmCalls(ortModule)
    : WasmCalls(ortModule);

/// `DATA_LOCATION_CPU`, from the enum in `onnxruntime/wasm/api.cc`. Zero is
/// `DATA_LOCATION_NONE` there and is refused for a tensor that has data.
const _dataLocationCpu = 1;

/// Base rather than final: the Asyncify backend is the same code except for
/// the five calls that can suspend, and re-implementing the rest would be two
/// copies to keep in step.
base class WasmCalls implements OrtCalls {
  WasmCalls(this.module);

  /// The module. Visible to the Asyncify backend, which calls the same
  /// exports through a different signature.
  @protected
  final OrtModule module;

  /// Options being built, by the handle handed out for them.
  ///
  /// The wasm build has no options object to mutate, so the seam's setters
  /// record here and [createSession] applies the lot.
  final _pending = <int, PendingSessionOptions>{};
  var _nextOptions = 1;

  @override
  void init({int loggingLevel = 2}) {
    // The same count the worker pool was sized with. Asking for more here than
    // the module was instantiated with means threads it cannot start.
    check(
      module,
      module.ortInit(ortWasmThreads.toJS, loggingLevel.toJS).toDartInt,
      'OrtInit',
    );
  }

  @override
  String runtimeVersion() => wasmRuntimeVersion;

  @override
  List<String> availableProviders() => const [
        // What every web build compiles in. The wasm build exports no way to
        // ask, and which accelerators are present depends on which of the
        // three builds was served, which this cannot see. WebGPU and WebNN
        // report themselves through the session when they are there.
        'CPUExecutionProvider',
        'XnnpackExecutionProvider',
      ];

  @override
  @NativeOnly('WebAssembly has no dlopen; providers are compiled into the '
      'build you serve')
  void registerProviderLibrary({required String name, required String path}) =>
      unsupportedOnWeb(
          'registerProviderLibrary',
          'WebAssembly has no dlopen. Serve the build that carries the '
              'provider you want instead');

  @override
  @NativeOnly('WebAssembly has no dlopen')
  void unregisterProviderLibrary(String name) => unsupportedOnWeb(
      'unregisterProviderLibrary', 'WebAssembly has no dlopen');

  // Session options are recorded rather than applied. See PendingSessionOptions.

  @override
  OrtPtr createSessionOptions() {
    final handle = _nextOptions++;
    _pending[handle] = PendingSessionOptions();
    return OrtPtr(handle);
  }

  /// The options recorded for [handle], for a subclass that builds them at a
  /// different moment.
  @protected
  PendingSessionOptions pendingOptions(OrtPtr handle) {
    final options = _pending[handle.address];
    if (options == null) {
      throw StateError('these session options were already released');
    }
    return options;
  }

  @override
  void appendExecutionProvider(
          OrtPtr options, String name, Map<String, String> configuration) =>
      pendingOptions(options).providers.add((name, configuration));

  @override
  void addSessionConfigEntry(OrtPtr options, String key, String value) =>
      pendingOptions(options).config[key] = value;

  @override
  @NativeOnly('WebAssembly has no dlopen; custom operators are compiled into '
      'the build you serve')
  void addCustomOpsLibrary(OrtPtr options, String path) => unsupportedOnWeb(
      'addCustomOpsLibrary',
      'WebAssembly has no dlopen. Custom operators have to be compiled into '
          'the runtime you serve');

  @override
  void addFreeDimensionOverride(OrtPtr options, String name, int dimension) =>
      pendingOptions(options).freeDimensions[name] = dimension;

  @override
  @NativeOnly('the thread count is fixed when the module is instantiated')
  void setIntraOpNumThreads(OrtPtr options, int threads) => unsupportedOnWeb(
      'setIntraOpNumThreads',
      'the WebAssembly build fixes its thread count at instantiation');

  @override
  @NativeOnly('the thread count is fixed when the module is instantiated')
  void setInterOpNumThreads(OrtPtr options, int threads) => unsupportedOnWeb(
      'setInterOpNumThreads',
      'the WebAssembly build fixes its thread count at instantiation');

  @override
  void setOptimizationLevel(OrtPtr options, OrtOptimizationLevel level) =>
      pendingOptions(options).setOptimization(level);

  @override
  void setExecutionMode(OrtPtr options, OrtExecutionMode mode) =>
      pendingOptions(options).setExecution(mode);

  @override
  void setLogLevel(OrtPtr options, OrtLogLevel level) =>
      pendingOptions(options).setLog(level);

  @override
  void setLogId(OrtPtr options, String id) =>
      pendingOptions(options).logId = id;

  @override
  @NativeOnly('this WebAssembly build is linked with FILESYSTEM=0')
  void setOptimizedModelPath(OrtPtr options, String path) => unsupportedOnWeb(
      'setOptimizedModelPath',
      'the WebAssembly build is compiled with FILESYSTEM=0');

  @override
  @NativeOnly('this WebAssembly build is linked with FILESYSTEM=0')
  void enableProfiling(OrtPtr options, String pathPrefix) => unsupportedOnWeb(
      'enableProfiling', 'the WebAssembly build is compiled with FILESYSTEM=0');

  @override
  @NativeOnly('the WebAssembly build exposes no deterministic compute flag')
  void setDeterministicCompute(OrtPtr options, {required bool deterministic}) =>
      unsupportedOnWeb('setDeterministicCompute',
          'the WebAssembly build exposes no such option');

  @override
  void setMemoryPattern(OrtPtr options, {required bool enabled}) =>
      pendingOptions(options).memoryPattern = enabled;

  @override
  void setCpuMemoryArena(OrtPtr options, {required bool enabled}) =>
      pendingOptions(options).cpuMemoryArena = enabled;

  @override
  void releaseSessionOptions(OrtPtr options) =>
      _pending.remove(options.address);

  @override
  OrtPtr createSession(Uint8List model, OrtPtr options) {
    final pending = pendingOptions(options);

    return withArena(module, (arena) {
      final built = buildOptions(arena, pending);
      try {
        // The runtime copies the graph during initialisation, so the model
        // only has to outlive this call.
        final data = arena.data(model);
        return checkHandle(
          module,
          module
              .ortCreateSession(data.toJS, model.lengthInBytes.toJS, built.toJS)
              .toDartInt,
          'OrtCreateSession',
        ).asPtr;
      } finally {
        module.ortReleaseSessionOptions(built.toJS);
      }
    });
  }

  /// Builds the real options object from what the setters recorded.
  @protected
  int buildOptions(WasmArena arena, PendingSessionOptions pending) {
    final handle = checkHandle(
      module,
      module
          .ortCreateSessionOptions(
            pending.optimizationLevel.toJS,
            pending.cpuMemoryArena.toJS,
            pending.memoryPattern.toJS,
            pending.executionMode.toJS,
            pending.profiling.toJS,
            _stringOrNull(arena, pending.profilePrefix).toJS,
            _stringOrNull(arena, pending.logId).toJS,
            pending.logSeverity.toJS,
            pending.logVerbosity.toJS,
            _stringOrNull(arena, pending.optimizedModelPath).toJS,
          )
          .toDartInt,
      'OrtCreateSessionOptions',
    );

    for (final entry in pending.config.entries) {
      check(
        module,
        module
            .ortAddSessionConfigEntry(handle.toJS, arena.string(entry.key).toJS,
                arena.string(entry.value).toJS)
            .toDartInt,
        'OrtAddSessionConfigEntry',
      );
    }

    for (final entry in pending.freeDimensions.entries) {
      check(
        module,
        module
            .ortAddFreeDimensionOverride(
                handle.toJS, arena.string(entry.key).toJS, entry.value.toJS)
            .toDartInt,
        'OrtAddFreeDimensionOverride',
      );
    }

    for (final (name, configuration) in pending.providers) {
      final keys = arena.strings(configuration.keys.toList());
      final values = arena.strings(configuration.values.toList());
      check(
        module,
        module
            .ortAppendExecutionProvider(handle.toJS, arena.string(name).toJS,
                keys.toJS, values.toJS, configuration.length.toJS)
            .toDartInt,
        'OrtAppendExecutionProvider',
      );
    }

    return handle;
  }

  int _stringOrNull(WasmArena arena, String? value) =>
      value == null ? 0 : arena.string(value);

  @override
  void releaseSession(OrtPtr session) =>
      module.ortReleaseSession(session.address.toJS);

  @override
  (int inputs, int outputs) inputOutputCount(OrtPtr session) =>
      withArena(module, (arena) {
        final slots = arena.slots(2);
        check(
          module,
          module
              .ortGetInputOutputCount(
                  session.address.toJS, slots.toJS, (slots + 4).toJS)
              .toDartInt,
          'OrtGetInputOutputCount',
        );
        return (module.readInt(slots), module.readInt(slots + 4));
      });

  @override
  OrtTensorMeta inputOutputMetadata(OrtPtr session, int index,
      {required bool input}) {
    return withArena(module, (arena) {
      final slots = arena.slots(2);
      // One call answers for inputs and outputs; the index is offset by the
      // input count when asking about an output.
      final counts = inputOutputCount(session);
      final at = input ? index : counts.$1 + index;

      check(
        module,
        module
            .ortGetInputOutputMetadata(
                session.address.toJS, at.toJS, slots.toJS, (slots + 4).toJS)
            .toDartInt,
        'OrtGetInputOutputMetadata',
      );

      final namePointer = module.readPointer(slots);
      final typeInfo = module.readPointer(slots + 4);
      try {
        return _metadata(module.readString(namePointer), typeInfo);
      } finally {
        // Both belong to the runtime and are handed over on success.
        module.ortFree(namePointer.toJS);
        module.ortFree(typeInfo.toJS);
      }
    });
  }

  /// Reads the packed type info the wasm build writes.
  ///
  /// The layout is documented in `OrtGetInputOutputMetadata`:
  ///
  ///     [0, 4)                    element type
  ///     [4, 8)                    dimension count
  ///     [8, 8 + n*4)              a name pointer per dimension, null unless
  ///                               that dimension is symbolic
  ///     [8 + n*4, 8 + n*8)        the dimension values
  ///
  /// A symbolic dimension is one the model decides at run time. The shared API
  /// reports those as -1, which is what the C API does natively.
  OrtTensorMeta _metadata(String name, int typeInfo) {
    if (typeInfo == 0) {
      return OrtTensorMeta(
        name: name,
        elementType: OrtElementType.undefined,
        shape: const [],
      );
    }

    final type = module.readInt(typeInfo);
    final rank = module.readInt(typeInfo + 4);
    final names = typeInfo + 8;
    final values = names + 4 * rank;

    final shape = <int>[
      for (var i = 0; i < rank; i++)
        if (module.readPointer(names + 4 * i) != 0)
          -1
        else
          module.readInt(values + 4 * i),
    ];

    return OrtTensorMeta(
      name: name,
      elementType: OrtElementType.fromCode(type),
      shape: shape,
    );
  }

  @override
  OrtPtr createTensor(OrtElementType type, TypedData data, List<int> shape) =>
      withArena(module, (arena) {
        // The runtime borrows the buffer rather than copying it, so this one
        // is not freed with the arena: the tensor owns it until release.
        final buffer = module.copyIn(data);
        final dimensions = arena.dimensions(shape);
        return checkHandle(
          module,
          module
              .ortCreateTensor(
                  type.code.toJS,
                  buffer.toJS,
                  data.lengthInBytes.toJS,
                  dimensions.toJS,
                  shape.length.toJS,
                  // DATA_LOCATION_CPU, from the enum in wasm/api.cc. Zero is
                  // "none" there, not the CPU, and is rejected.
                  _dataLocationCpu.toJS)
              .toDartInt,
          'OrtCreateTensor',
        ).asPtr;
      });

  @override
  @NativeOnly('the WebAssembly build exports no string tensor path')
  OrtPtr createStringTensor(List<String> values, List<int> shape) =>
      unsupportedOnWeb('createStringTensor',
          'the WebAssembly build exports no string tensor path');

  @override
  OrtTensorView tensorData(OrtPtr tensor) => withArena(module, (arena) {
        final slots = arena.slots(4);
        check(
          module,
          module
              .ortGetTensorData(tensor.address.toJS, slots.toJS,
                  (slots + 4).toJS, (slots + 8).toJS, (slots + 12).toJS)
              .toDartInt,
          'OrtGetTensorData',
        );

        final type = OrtElementType.fromCode(module.readInt(slots));
        final data = module.readPointer(slots + 4);
        final dimensions = module.readPointer(slots + 8);
        final rank = module.readInt(slots + 12);

        final shape = [
          for (var i = 0; i < rank; i++) module.readInt(dimensions + 4 * i),
        ];
        final elements = shape.fold(1, (total, size) => total * size);

        // Copied out. The heap moves when it grows, so a view into it is only
        // valid until the next allocation.
        final bytes = module.copyOut(data, elements * (type.byteWidth ?? 1));
        module.ortFree(dimensions.toJS);
        return OrtTensorView(elementType: type, shape: shape, data: bytes);
      });

  @override
  @NativeOnly('the WebAssembly build exports no string tensor path')
  List<String> stringTensorData(OrtPtr tensor) => unsupportedOnWeb(
      'stringTensorData',
      'the WebAssembly build exports no string tensor path');

  @override
  void releaseTensor(OrtPtr tensor) =>
      module.ortReleaseTensor(tensor.address.toJS);

  @override
  OrtPtr createRunOptions() => checkHandle(
        module,
        module
            .ortCreateRunOptions(2.toJS, 0.toJS, false.toJS, 0.toJS)
            .toDartInt,
        'OrtCreateRunOptions',
      ).asPtr;

  @override
  void addRunConfigEntry(OrtPtr runOptions, String key, String value) =>
      withArena(module, (arena) {
        check(
          module,
          module
              .ortAddRunConfigEntry(runOptions.address.toJS,
                  arena.string(key).toJS, arena.string(value).toJS)
              .toDartInt,
          'OrtAddRunConfigEntry',
        );
      });

  @override
  void releaseRunOptions(OrtPtr runOptions) =>
      module.ortReleaseRunOptions(runOptions.address.toJS);

  @override
  List<OrtPtr> run(OrtPtr session, Map<String, OrtPtr> inputs,
          List<String> outputNames, OrtPtr runOptions) =>
      withArena(module, (arena) {
        final names = arena.strings(inputs.keys.toList());
        final values =
            arena.handles([for (final v in inputs.values) v.address]);
        final wanted = arena.strings(outputNames);
        final results = arena.slots(outputNames.length);

        check(
          module,
          module
              .ortRun(
                  session.address.toJS,
                  names.toJS,
                  values.toJS,
                  inputs.length.toJS,
                  wanted.toJS,
                  outputNames.length.toJS,
                  results.toJS,
                  runOptions.address.toJS)
              .toDartInt,
          'OrtRun',
        );

        return [
          for (var i = 0; i < outputNames.length; i++)
            OrtPtr(module.readPointer(results + 4 * i)),
        ];
      });

  @override
  OrtPtr createBinding(OrtPtr session) => checkHandle(
        module,
        module.ortCreateBinding(session.address.toJS).toDartInt,
        'OrtCreateBinding',
      ).asPtr;

  @override
  void bindInput(OrtPtr binding, String name, OrtPtr tensor) =>
      withArena(module, (arena) {
        check(
          module,
          module
              .ortBindInput(binding.address.toJS, arena.string(name).toJS,
                  tensor.address.toJS)
              .toDartInt,
          'OrtBindInput',
        );
      });

  @override
  void bindOutput(OrtPtr binding, String name, OrtPtr tensor) =>
      withArena(module, (arena) {
        check(
          module,
          module
              .ortBindOutput(binding.address.toJS, arena.string(name).toJS,
                  tensor.address.toJS, _dataLocationCpu.toJS)
              .toDartInt,
          'OrtBindOutput',
        );
      });

  @override
  @NativeOnly('the WebAssembly build clears bound outputs only')
  void clearBoundInputs(OrtPtr binding) => unsupportedOnWeb('clearBoundInputs',
      'the WebAssembly build exports no way to clear bound inputs');

  @override
  void clearBoundOutputs(OrtPtr binding) => check(
        module,
        module.ortClearBoundOutputs(binding.address.toJS).toDartInt,
        'OrtClearBoundOutputs',
      );

  @override
  void runWithBinding(OrtPtr session, OrtPtr binding, OrtPtr runOptions) =>
      withArena(module, (arena) {
        final count = arena.slots();
        check(
          module,
          module
              .ortRunWithBinding(session.address.toJS, binding.address.toJS,
                  0.toJS, count.toJS, runOptions.address.toJS)
              .toDartInt,
          'OrtRunWithBinding',
        );
      });

  @override
  void releaseBinding(OrtPtr binding) =>
      module.ortReleaseBinding(binding.address.toJS);

  @override
  String? endProfiling(OrtPtr session) {
    final pointer = module.ortEndProfiling(session.address.toJS).toDartInt;
    if (pointer == 0) return null;
    try {
      return module.readString(pointer);
    } finally {
      module.ortFree(pointer.toJS);
    }
  }
}

/// A heap offset the runtime handed back, as the currency the seam deals in.
extension on int {
  OrtPtr get asPtr => OrtPtr(this);
}

/// Loading a model and running it.
///
/// Shared code: no `dart:ffi` here, so this is the same class on native and on
/// the web. Everything platform-specific is behind [OrtCalls].
library;

import 'dart:typed_data';

import 'backend/calls.dart';
import 'backend/interface.dart';
import 'backend/types.dart';
import 'handle.dart';

/// The version of ONNX Runtime that is loaded, such as `1.29.0`.
String runtimeVersion() => createCalls().runtimeVersion();

/// The execution providers this build was compiled with.
///
/// A provider not in this list cannot be requested by name, though one can
/// still be loaded from a plugin library at run time.
List<String> availableProviders() => createCalls().availableProviders();

/// Loads an execution provider plugin from [path], under [name].
///
/// A plugin is a shared library exporting `CreateEpFactories`, which is how a
/// provider ships separately from the runtime. [name] then names it in
/// [SessionOptions.providers].
///
/// Call this before creating any session. It mutates process-global state, and
/// racing it against session creation crashes the runtime rather than failing.
/// Ordering is not the constraint: ONNX Runtime is happy to register a
/// provider after sessions already exist, and they simply keep what they were
/// built with.
void registerProviderLibrary({required String name, required String path}) =>
    createCalls().registerProviderLibrary(name: name, path: path);

/// Unloads the plugin registered under [name].
void unregisterProviderLibrary(String name) =>
    createCalls().unregisterProviderLibrary(name);

/// How a session is configured, applied when it is created.
///
/// Only settings that change how a model loads belong here. Everything else is
/// a call on the session, or one of the several hundred wrappers in
/// `native.dart` for the parts this does not cover.
final class SessionOptions {
  const SessionOptions({
    this.providers = const [],
    this.config = const {},
    this.freeDimensionOverrides = const {},
    this.intraOpNumThreads,
    this.interOpNumThreads,
    this.optimizationLevel,
    this.executionMode,
    this.logLevel,
    this.logId,
    this.optimizedModelPath,
    this.profileFilePrefix,
    this.deterministicCompute,
    this.memoryPattern,
    this.cpuMemoryArena,
    this.customOpsLibraries = const [],
  });

  /// Execution providers to try, in order, each with its own configuration.
  ///
  /// A provider that is not present in the build is an error rather than a
  /// silent fall back to CPU, because the difference is a hundredfold in speed
  /// and nothing else would report it.
  final List<({String name, Map<String, String> configuration})> providers;

  /// Session config entries, keyed by the constants in `config_keys.g.dart`.
  final Map<String, String> config;

  /// Fixes a symbolic dimension to a concrete size, by name.
  ///
  /// A model with a dynamic batch dimension can be optimised further once the
  /// size is known.
  final Map<String, int> freeDimensionOverrides;

  /// Threads ONNX Runtime may use within a single operator.
  ///
  /// Null leaves the runtime's default, which sizes the pool to the machine.
  /// One means no parallelism, which also rules out [Session.runAsync]: that
  /// dispatches onto this pool, so with one thread there is nothing to dispatch
  /// to.
  final int? intraOpNumThreads;

  /// Threads for running independent branches of the graph at the same time.
  ///
  /// Only used when [executionMode] is [OrtExecutionMode.parallel], and only
  /// helps a graph that branches.
  final int? interOpNumThreads;

  /// How much the graph is rewritten before it runs.
  final OrtOptimizationLevel? optimizationLevel;

  final OrtExecutionMode? executionMode;

  /// How much this session logs. Null leaves the environment's level.
  final OrtLogLevel? logLevel;

  /// Tags this session's log lines, which is how you tell two apart.
  final String? logId;

  /// Writes the optimised graph here, to inspect or to load instead later.
  final String? optimizedModelPath;

  /// Turns on profiling, writing files starting with this prefix.
  ///
  /// [Session.endProfiling] stops it and returns the file it wrote.
  final String? profileFilePrefix;

  /// Trades speed for reproducible results between runs.
  final bool? deterministicCompute;

  /// Reuses one allocation across a run, planned from the graph's shapes.
  ///
  /// On by default, and worth turning off only for a model whose shapes change
  /// every run, where the plan is recomputed and never reused.
  final bool? memoryPattern;

  /// Keeps an arena for CPU allocations rather than returning them each time.
  final bool? cpuMemoryArena;

  /// Libraries of custom operators to load, by path.
  ///
  /// A model can name operators ONNX Runtime does not have. Anyone can build
  /// one: it is a shared library exporting `RegisterCustomOps`, and nothing
  /// about it is specific to this package.
  ///
  /// A package shipping one as a code asset does not know where it landed, so
  /// ask the loader rather than guessing at a layout:
  ///
  /// ```dart
  /// @Native<Void Function()>(
  ///   symbol: 'RegisterCustomOps',
  ///   assetId: 'package:my_ops/library',
  /// )
  /// external void _entryPoint();
  ///
  /// final path = libraryPathOf(
  ///   Native.addressOf<NativeFunction<Void Function()>>(_entryPoint).cast(),
  /// );
  /// ```
  final List<String> customOpsLibraries;

  /// Applies every setting that was given, leaving the rest at the runtime's
  /// default. Null means "not asked for", which is not the same as false.
  void _applyTo(OrtCalls calls, OrtPtr options) {
    for (final provider in providers) {
      calls.appendExecutionProvider(
        options,
        provider.name,
        provider.configuration,
      );
    }
    for (final entry in config.entries) {
      calls.addSessionConfigEntry(options, entry.key, entry.value);
    }
    for (final entry in freeDimensionOverrides.entries) {
      calls.addFreeDimensionOverride(options, entry.key, entry.value);
    }

    if (intraOpNumThreads case final threads?) {
      calls.setIntraOpNumThreads(options, threads);
    }
    if (interOpNumThreads case final threads?) {
      calls.setInterOpNumThreads(options, threads);
    }
    if (optimizationLevel case final level?) {
      calls.setOptimizationLevel(options, level);
    }
    if (executionMode case final mode?) {
      calls.setExecutionMode(options, mode);
    }
    if (logLevel case final level?) calls.setLogLevel(options, level);
    if (logId case final id?) calls.setLogId(options, id);
    if (optimizedModelPath case final path?) {
      calls.setOptimizedModelPath(options, path);
    }
    if (profileFilePrefix case final prefix?) {
      calls.enableProfiling(options, prefix);
    }
    if (deterministicCompute case final deterministic?) {
      calls.setDeterministicCompute(options, deterministic: deterministic);
    }
    if (memoryPattern case final enabled?) {
      calls.setMemoryPattern(options, enabled: enabled);
    }
    if (cpuMemoryArena case final enabled?) {
      calls.setCpuMemoryArena(options, enabled: enabled);
    }
    for (final path in customOpsLibraries) {
      calls.addCustomOpsLibrary(options, path);
    }
  }
}

/// A loaded model.
///
/// Isolate-local, and not sendable: create one where it is used. Loading runs
/// the graph optimisation passes, which is the expensive part, so a worker that
/// serves many requests should build one session and keep it.
final class Session {
  Session._(
    this._calls,
    this._handle,
    this._intraOpNumThreads,
    this.inputs,
    this.outputs,
  );

  /// Loads a model from [model].
  ///
  /// From bytes only. Loading by path would mean `ORTCHAR_T`, which is UTF-16
  /// on Windows, for no gain over reading the file first.
  factory Session.fromBytes(
    Uint8List model, {
    SessionOptions options = const SessionOptions(),
  }) {
    final calls = createCalls()..init();
    final optionsPtr = calls.createSessionOptions();
    try {
      options._applyTo(calls, optionsPtr);

      final session = calls.createSession(model, optionsPtr);
      return Session._fromHandle(calls, session, options.intraOpNumThreads);
    } finally {
      // The session holds its own copy of everything it needed from these.
      calls.releaseSessionOptions(optionsPtr);
    }
  }

  /// Loads a model, awaiting the runtime if it needs to.
  ///
  /// The same thing [Session.fromBytes] does, and on every platform but one it
  /// completes immediately. The exception is a WebGPU or WebNN build on the
  /// web: those are compiled with Asyncify, where creating a session can
  /// suspend while the GPU is set up, and the synchronous form has no way to
  /// wait for it.
  ///
  /// Use this if the code has to run everywhere. Use [Session.fromBytes] when
  /// it does not, or when the extra `await` is not worth it.
  static Future<Session> load(
    Uint8List model, {
    SessionOptions options = const SessionOptions(),
  }) async {
    final calls = createCalls()..init();
    if (calls is! OrtAsyncSessionCalls) {
      // Every backend but the Asyncify ones. Creating a session cannot
      // suspend there, so there is nothing to await.
      return Session.fromBytes(model, options: options);
    }
    final creator = calls as OrtAsyncSessionCalls;

    final optionsPtr = calls.createSessionOptions();
    try {
      options._applyTo(calls, optionsPtr);
      final session = await creator.createSessionAsync(model, optionsPtr);
      return Session._fromHandle(calls, session, options.intraOpNumThreads);
    } finally {
      calls.releaseSessionOptions(optionsPtr);
    }
  }

  /// Reads a session's signature and wraps it, releasing it if that fails.
  ///
  /// Shared by both constructors: nothing owns the session until this returns,
  /// and the finalizer is not a plan.
  static Session _fromHandle(
    OrtCalls calls,
    OrtPtr session,
    int? intraOpNumThreads,
  ) {
    final handle = OrtHandle(session, calls.releaseSession, 'OrtSession');
    try {
      final (inputCount, outputCount) = calls.inputOutputCount(session);
      return Session._(
        calls,
        handle,
        intraOpNumThreads,
        List.unmodifiable([
          for (var i = 0; i < inputCount; i++)
            calls.inputOutputMetadata(session, i, input: true),
        ]),
        List.unmodifiable([
          for (var i = 0; i < outputCount; i++)
            calls.inputOutputMetadata(session, i, input: false),
        ]),
      );
    } on Object {
      handle.release();
      rethrow;
    }
  }

  final OrtCalls _calls;
  final OrtHandle _handle;
  final int? _intraOpNumThreads;

  /// What the model expects, in order. Unmodifiable.
  final List<OrtTensorMeta> inputs;

  /// What the model produces, in order. Unmodifiable.
  final List<OrtTensorMeta> outputs;

  /// Runs the model.
  ///
  /// [feeds] is keyed by input name; every entry in [inputs] must be present.
  /// Returns one entry per requested output, keyed by name.
  ///
  /// [wanted] names the outputs to compute, defaulting to all of them. Asking
  /// for fewer is not just less to read back: ONNX Runtime only executes the
  /// part of the graph those outputs depend on.
  Map<String, OrtTensor> run(
    Map<String, OrtTensor> feeds, {
    List<String>? wanted,
  }) {
    _check(feeds);
    final names = _wanted(wanted);
    final runOptions = _calls.createRunOptions();
    try {
      final results = _calls.run(
        _handle.pointer,
        {for (final e in feeds.entries) e.key: e.value._handle.pointer},
        names,
        runOptions,
      );
      return {
        for (final (index, name) in names.indexed)
          name: OrtTensor._(_calls, results[index]),
      };
    } finally {
      _calls.releaseRunOptions(runOptions);
    }
  }

  /// Runs the model, waiting for the runtime rather than blocking on it.
  ///
  /// On native the work happens on ONNX Runtime's own thread pool and the
  /// result arrives on this isolate's event loop, so one session can have
  /// several runs in flight against one copy of the weights.
  ///
  /// On the web it is whichever the build offers. A WebGPU or WebNN build is
  /// compiled with Asyncify and genuinely suspends while the GPU works. The
  /// plain build exports no asynchronous run and never needs one, so this
  /// completes with the result of the synchronous run.
  ///
  /// Use this if the code has to run everywhere. It is the counterpart of
  /// [Session.load], and like it, it works on every build.
  Future<Map<String, OrtTensor>> runAsync(
    Map<String, OrtTensor> feeds, {
    List<String>? wanted,
  }) async {
    if (_calls is! OrtAsyncCalls) {
      // The plain WebAssembly build. Nothing there can suspend, so the
      // synchronous run is the entire implementation: this is the same work
      // with a future around it, not a degraded version of it.
      return run(feeds, wanted: wanted);
    }
    final calls = _calls as OrtAsyncCalls;

    // Only where the run is dispatched onto a thread pool. A build that
    // suspends instead, which is every backend that can also create a session
    // asynchronously, has no pool to be short of.
    if (_calls is! OrtAsyncSessionCalls && _intraOpNumThreads == 1) {
      throw StateError(
        'runAsync needs at least two intra-op threads, and this session was '
        'created with one. ONNX Runtime dispatches the run onto that pool and '
        'rejects it below two.',
      );
    }
    _check(feeds);
    final names = _wanted(wanted);

    final runOptions = _calls.createRunOptions();
    try {
      final results = await calls.runAsync(
        _handle.pointer,
        {for (final e in feeds.entries) e.key: e.value._handle.pointer},
        names,
        runOptions,
      );
      return {
        for (final (index, name) in names.indexed)
          name: OrtTensor._(_calls, results[index]),
      };
    } finally {
      _calls.releaseRunOptions(runOptions);
    }
  }

  /// Stops profiling and returns the file it was written to.
  ///
  /// Null unless profiling was enabled in [SessionOptions.config].
  String? endProfiling() => _calls.endProfiling(_handle.pointer);

  /// Frees the model now rather than waiting for collection.
  void release() => _handle.release();

  /// The output names to ask for, defaulting to every one the model has.
  List<String> _wanted(List<String>? requested) {
    if (requested == null) return [for (final output in outputs) output.name];

    final known = {for (final output in outputs) output.name};
    final unknown = requested.toSet().difference(known);
    if (unknown.isNotEmpty) {
      throw ArgumentError.value(
        requested,
        'wanted',
        'the model has no output named ${unknown.join(', ')}',
      );
    }
    if (requested.isEmpty) {
      throw ArgumentError.value(requested, 'wanted', 'asks for no outputs');
    }
    return requested;
  }

  void _check(Map<String, OrtTensor> feeds) {
    final missing =
        inputs.map((i) => i.name).toSet().difference(feeds.keys.toSet());
    if (missing.isNotEmpty) {
      throw ArgumentError.value(
        feeds.keys.toList(),
        'feeds',
        'the model needs ${missing.join(', ')}',
      );
    }
  }
}

/// A tensor, owned by whoever created it.
///
/// Dropping the reference frees it; [release] frees it now. Both are safe, and
/// releasing twice throws rather than double-freeing.
final class OrtTensor {
  OrtTensor._(this._calls, OrtPtr pointer)
      : _handle = OrtHandle(pointer, _calls.releaseTensor, 'OrtValue');

  /// Creates a tensor holding a copy of [data], laid out row-major.
  ///
  /// The element count implied by [shape] must match what [data] holds.
  factory OrtTensor.fromData(
    OrtElementType type,
    TypedData data,
    List<int> shape,
  ) {
    if (type == OrtElementType.string) {
      throw ArgumentError.value(
        type,
        'type',
        'strings are not stored as bytes; use OrtTensor.fromStrings',
      );
    }

    // The size check lives with the write, in the backend, because that is
    // where getting it wrong runs off the end of an allocation.
    final calls = createCalls()..init();
    return OrtTensor._(calls, calls.createTensor(type, data, shape));
  }

  /// Creates a string tensor holding [values], laid out row-major.
  factory OrtTensor.fromStrings(List<String> values, List<int> shape) {
    final calls = createCalls()..init();
    return OrtTensor._(calls, calls.createStringTensor(values, shape));
  }

  final OrtCalls _calls;
  final OrtHandle _handle;

  /// The type, shape and bytes, borrowed from the tensor.
  ///
  /// The bytes are the tensor's own buffer. Copy them if they need to outlive
  /// it.
  OrtTensorView get view => _calls.tensorData(_handle.pointer);

  /// The contents of a string tensor, in row-major order.
  List<String> get strings => _calls.stringTensorData(_handle.pointer);

  /// Frees the tensor now rather than waiting for collection.
  void release() => _handle.release();
}

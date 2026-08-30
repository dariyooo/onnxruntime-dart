/// The seam, over `dart:ffi`.
///
/// Thin by construction: the generated wrappers already marshal, check the
/// status and free what they allocated, so most methods here are a pointer
/// conversion around one call. What is written out by hand is what a generator
/// cannot know, which is ownership.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../bindings/api/api.g.dart';
import '../bindings/api/support.dart';
import '../bindings/ort_bindings.g.dart';
import '../ffi/environment.dart';
import '../ffi/runtime.dart' as ffi;
import '../ffi/status.dart';
import 'interface.dart';
import 'types.dart';

/// Returns the backend for this platform.
OrtCalls createCalls() => FfiCalls();

/// `OrtCalls` implemented against the ONNX Runtime C API.
final class FfiCalls implements OrtCalls, OrtAsyncCalls {
  FfiCalls._(this._environment);

  static FfiCalls? _instance;

  /// The backend for this isolate.
  ///
  /// The environment underneath is process-wide and thread-safe, so this is a
  /// lookup rather than a resource.
  factory FfiCalls() => _instance ??= FfiCalls._(OrtEnvironment.instance());

  final OrtEnvironment _environment;

  OrtApi get _api => _environment.api;

  /// The default allocator, which is what every allocator-taking call here
  /// uses. It is owned by the runtime and must not be released.
  late final Pointer<OrtAllocator> _allocator =
      _api.getAllocatorWithDefaultOptions();

  @override
  void init({int loggingLevel = 3}) => OrtEnvironment.instance();

  @override
  String runtimeVersion() => ffi.runtimeVersion();

  @override
  OrtPtr createSessionOptions() => _ptr(_api.createSessionOptions());

  @override
  void appendExecutionProvider(
    OrtPtr options,
    String name,
    Map<String, String> configuration,
  ) =>
      _api.sessionOptionsAppendExecutionProvider(
        _as<OrtSessionOptions>(options),
        name,
        configuration.keys.toList(),
        configuration.values.toList(),
        configuration.length,
      );

  @override
  void addSessionConfigEntry(OrtPtr options, String key, String value) =>
      _api.addSessionConfigEntry(_as<OrtSessionOptions>(options), key, value);

  @override
  void addFreeDimensionOverride(OrtPtr options, String name, int dimension) =>
      _api.addFreeDimensionOverrideByName(
        _as<OrtSessionOptions>(options),
        name,
        dimension,
      );

  @override
  void setIntraOpNumThreads(OrtPtr options, int threads) =>
      _api.setIntraOpNumThreads(_as<OrtSessionOptions>(options), threads);

  @override
  void releaseSessionOptions(OrtPtr options) =>
      _api.releaseSessionOptions(_as<OrtSessionOptions>(options));

  @override
  OrtPtr createSession(Uint8List model, OrtPtr options) => withArena((arena) {
        // ORT copies the graph during initialisation, so the buffer only has
        // to outlive the call.
        final buffer = arena<Uint8>(model.length);
        buffer.asTypedList(model.length).setAll(0, model);
        return _ptr(
          _api.createSessionFromArray(
            _environment.handle,
            buffer.cast(),
            model.length,
            _as<OrtSessionOptions>(options),
          ),
        );
      });

  @override
  void releaseSession(OrtPtr session) =>
      _api.releaseSession(_as<OrtSession>(session));

  @override
  (int inputs, int outputs) inputOutputCount(OrtPtr session) {
    final handle = _as<OrtSession>(session);
    return (
      _api.sessionGetInputCount(handle),
      _api.sessionGetOutputCount(handle),
    );
  }

  @override
  OrtTensorMeta inputOutputMetadata(
    OrtPtr session,
    int index, {
    required bool input,
  }) {
    final handle = _as<OrtSession>(session);
    final name = input
        ? _api.sessionGetInputName(handle, index, _allocator)
        : _api.sessionGetOutputName(handle, index, _allocator);

    final info = input
        ? _api.sessionGetInputTypeInfo(handle, index)
        : _api.sessionGetOutputTypeInfo(handle, index);
    try {
      // Borrowed from the type info, so it must not be released separately.
      final tensor = _api.castTypeInfoToTensorInfo(info);
      return OrtTensorMeta(
        name: name,
        elementType: OrtElementType.fromCode(_api.getTensorElementType(tensor)),
        shape: _api.getDimensions(tensor, _api.getDimensionsCount(tensor)),
      );
    } finally {
      _api.releaseTypeInfo(info);
    }
  }

  @override
  OrtPtr createTensor(
    OrtElementType type,
    TypedData data,
    List<int> shape,
  ) {
    // Allocator-backed rather than `CreateTensorWithDataAsOrtValue`, which
    // borrows the buffer it is given and would outlive an arena. Here the
    // tensor owns its memory, so its lifetime is the only one to reason about.
    final tensor = _api.createTensorAsOrtValue(
      _allocator,
      shape,
      shape.length,
      type.code,
    );
    try {
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      _tensorBytes(tensor, bytes.length).setAll(0, bytes);
      return _ptr(tensor);
    } on Object {
      _api.releaseValue(tensor);
      rethrow;
    }
  }

  @override
  OrtPtr createStringTensor(List<String> values, List<int> shape) {
    final tensor = _api.createTensorAsOrtValue(
      _allocator,
      shape,
      shape.length,
      OrtElementType.string.code,
    );
    try {
      _api.fillStringTensor(tensor, values, values.length);
      return _ptr(tensor);
    } on Object {
      _api.releaseValue(tensor);
      rethrow;
    }
  }

  @override
  OrtTensorView tensorData(OrtPtr tensor) {
    final handle = _as<OrtValue>(tensor);
    final info = _api.getTensorTypeAndShape(handle);
    try {
      final type = OrtElementType.fromCode(_api.getTensorElementType(info));
      final shape = _api.getDimensions(info, _api.getDimensionsCount(info));
      final width = type.byteWidth;
      if (width == null) {
        throw StateError(
          'a ${type.name} tensor has no fixed-width representation; '
          'read it with stringTensorData',
        );
      }
      return OrtTensorView(
        elementType: type,
        shape: shape,
        data: _tensorBytes(
          handle,
          _api.getTensorShapeElementCount(info) * width,
        ),
      );
    } finally {
      _api.releaseTensorTypeAndShapeInfo(info);
    }
  }

  @override
  List<String> stringTensorData(OrtPtr tensor) {
    final handle = _as<OrtValue>(tensor);
    final info = _api.getTensorTypeAndShape(handle);
    final count = _api.getTensorShapeElementCount(info);
    _api.releaseTensorTypeAndShapeInfo(info);

    // The contents are one concatenated buffer plus the offset of each element.
    // `GetStringTensorContent` writes into a caller-provided buffer, which the
    // generated wrappers do not express.
    final bytes = _api.getStringTensorDataLength(handle);
    return withArena((arena) {
      final buffer = arena<Uint8>(bytes == 0 ? 1 : bytes);
      final offsets = arena<Size>(count == 0 ? 1 : count);
      checkStatus(
        _api,
        _api.GetStringTensorContent.asFunction<
            Pointer<OrtStatus> Function(
              Pointer<OrtValue>,
              Pointer<Void>,
              int,
              Pointer<Size>,
              int,
            )>()(handle, buffer.cast(), bytes, offsets, count),
      );

      // The offsets say where each element starts; the last one runs to the
      // end of the buffer.
      final content = buffer.asTypedList(bytes);
      return [
        for (var i = 0; i < count; i++)
          utf8.decode(
            content.sublist(offsets[i], i + 1 < count ? offsets[i + 1] : bytes),
          ),
      ];
    });
  }

  @override
  void releaseTensor(OrtPtr tensor) => _api.releaseValue(_as<OrtValue>(tensor));

  @override
  OrtPtr createRunOptions() => _ptr(_api.createRunOptions());

  @override
  void addRunConfigEntry(OrtPtr runOptions, String key, String value) =>
      _api.addRunConfigEntry(_as<OrtRunOptions>(runOptions), key, value);

  @override
  void releaseRunOptions(OrtPtr runOptions) =>
      _api.releaseRunOptions(_as<OrtRunOptions>(runOptions));

  @override
  List<OrtPtr> run(
    OrtPtr session,
    Map<String, OrtPtr> inputs,
    List<String> outputNames,
    OrtPtr runOptions,
  ) =>
      withArena((arena) {
        // `Run` takes its outputs as an `_Inout_` array it writes into, so the
        // array has to outlive the call to be read. The generated wrapper
        // allocates one per call and drops it, which is why this is by hand.
        final outputs = arena<Pointer<OrtValue>>(
          outputNames.isEmpty ? 1 : outputNames.length,
        );
        for (var i = 0; i < outputNames.length; i++) {
          outputs[i] = nullptr;
        }

        checkStatus(
          _api,
          _api.Run.asFunction<
              Pointer<OrtStatus> Function(
                Pointer<OrtSession>,
                Pointer<OrtRunOptions>,
                Pointer<Pointer<Char>>,
                Pointer<Pointer<OrtValue>>,
                int,
                Pointer<Pointer<Char>>,
                int,
                Pointer<Pointer<OrtValue>>,
              )>()(
            _as<OrtSession>(session),
            _as<OrtRunOptions>(runOptions),
            nativeStrings(inputs.keys.toList(), arena),
            nativePointers(
              [for (final v in inputs.values) _as<OrtValue>(v)],
              arena,
            ),
            inputs.length,
            nativeStrings(outputNames, arena),
            outputNames.length,
            outputs,
          ),
        );

        return [
          for (var i = 0; i < outputNames.length; i++) _ptr(outputs[i]),
        ];
      });

  @override
  Future<List<OrtPtr>> runAsync(
    OrtPtr session,
    Map<String, OrtPtr> inputs,
    List<String> outputNames,
    OrtPtr runOptions,
  ) {
    // Everything the call touches has to outlive it: ORT reads the name and
    // value arrays on its own thread and writes the outputs there too, long
    // after this function has returned. So it is malloc, freed once in the
    // callback, rather than an arena scoped to the call.
    final arrays = _AsyncArrays(inputs, outputNames);
    final completer = Completer<List<OrtPtr>>();

    late final NativeCallable<RunAsyncCallbackFnFunction> callback;
    void complete(
      Pointer<Void> _,
      Pointer<Pointer<OrtValue>> outputs,
      int count,
      Pointer<OrtStatus> status,
    ) {
      // Runs on the calling isolate's event loop, not ORT's thread, because
      // the callable is a listener. Ordinary Dart rules apply here.
      final failure = readStatus(_api, status);
      final results = failure != null
          ? const <OrtPtr>[]
          : [for (var i = 0; i < count; i++) _ptr(outputs[i])];

      arrays.free();
      callback.close();

      if (failure != null) {
        completer.completeError(failure);
      } else {
        completer.complete(results);
      }
    }

    callback = NativeCallable<RunAsyncCallbackFnFunction>.listener(complete);

    try {
      checkStatus(
        _api,
        _api.RunAsync.asFunction<
            Pointer<OrtStatus> Function(
              Pointer<OrtSession>,
              Pointer<OrtRunOptions>,
              Pointer<Pointer<Char>>,
              Pointer<Pointer<OrtValue>>,
              int,
              Pointer<Pointer<Char>>,
              int,
              Pointer<Pointer<OrtValue>>,
              RunAsyncCallbackFn,
              Pointer<Void>,
            )>()(
          _as<OrtSession>(session),
          _as<OrtRunOptions>(runOptions),
          arrays.inputNames,
          arrays.inputs,
          inputs.length,
          arrays.outputNames,
          outputNames.length,
          arrays.outputs,
          callback.nativeFunction,
          nullptr,
        ),
      );
    } on Object {
      // The call never started, so the callback will not fire and nothing else
      // will clean up after it.
      arrays.free();
      callback.close();
      rethrow;
    }

    return completer.future;
  }

  @override
  OrtPtr createBinding(OrtPtr session) =>
      _ptr(_api.createIoBinding(_as<OrtSession>(session)));

  @override
  void bindInput(OrtPtr binding, String name, OrtPtr tensor) =>
      _api.bindInput(_as<OrtIoBinding>(binding), name, _as<OrtValue>(tensor));

  @override
  void bindOutput(OrtPtr binding, String name, OrtPtr tensor) =>
      _api.bindOutput(_as<OrtIoBinding>(binding), name, _as<OrtValue>(tensor));

  @override
  void clearBoundInputs(OrtPtr binding) =>
      _api.clearBoundInputs(_as<OrtIoBinding>(binding));

  @override
  void clearBoundOutputs(OrtPtr binding) =>
      _api.clearBoundOutputs(_as<OrtIoBinding>(binding));

  @override
  void runWithBinding(OrtPtr session, OrtPtr binding, OrtPtr runOptions) =>
      _api.runWithBinding(
        _as<OrtSession>(session),
        _as<OrtRunOptions>(runOptions),
        _as<OrtIoBinding>(binding),
      );

  @override
  void releaseBinding(OrtPtr binding) =>
      _api.releaseIoBinding(_as<OrtIoBinding>(binding));

  @override
  String? endProfiling(OrtPtr session) =>
      _api.sessionEndProfiling(_as<OrtSession>(session), _allocator);

  /// The tensor's own buffer, as bytes. Borrowed: valid while the tensor is.
  Uint8List _tensorBytes(Pointer<OrtValue> tensor, int length) =>
      _api.getTensorMutableData(tensor).cast<Uint8>().asTypedList(length);
}

/// The arrays `RunAsync` borrows until its callback fires.
///
/// One owner, one free. Grouped rather than tracked as eight locals because
/// the failure mode of missing one is a leak per call.
final class _AsyncArrays {
  _AsyncArrays(Map<String, OrtPtr> inputs, List<String> outputNames)
      : inputNames = _strings(inputs.keys),
        outputNames = _strings(outputNames),
        inputs = calloc<Pointer<OrtValue>>(_atLeastOne(inputs.length)),
        outputs = calloc<Pointer<OrtValue>>(_atLeastOne(outputNames.length)),
        _inputCount = inputs.length,
        _outputCount = outputNames.length {
    var i = 0;
    for (final value in inputs.values) {
      this.inputs[i++] = _as<OrtValue>(value);
    }
  }

  final Pointer<Pointer<Char>> inputNames;
  final Pointer<Pointer<Char>> outputNames;
  final Pointer<Pointer<OrtValue>> inputs;
  final Pointer<Pointer<OrtValue>> outputs;
  final int _inputCount;
  final int _outputCount;

  var _freed = false;

  void free() {
    if (_freed) return;
    _freed = true;
    for (var i = 0; i < _inputCount; i++) {
      calloc.free(inputNames[i]);
    }
    for (var i = 0; i < _outputCount; i++) {
      calloc.free(outputNames[i]);
    }
    calloc
      ..free(inputNames)
      ..free(outputNames)
      ..free(inputs)
      ..free(outputs);
  }

  static Pointer<Pointer<Char>> _strings(Iterable<String> values) {
    final list = values.toList();
    final array = calloc<Pointer<Char>>(_atLeastOne(list.length));
    for (var i = 0; i < list.length; i++) {
      array[i] = list[i].toNativeUtf8(allocator: calloc).cast();
    }
    return array;
  }

  /// `calloc<T>(0)` is not meaningful, and a model can take no inputs.
  static int _atLeastOne(int count) => count == 0 ? 1 : count;
}

Pointer<T> _as<T extends NativeType>(OrtPtr pointer) =>
    Pointer<T>.fromAddress(pointer.address);

OrtPtr _ptr(Pointer<NativeType> pointer) => OrtPtr(pointer.address);

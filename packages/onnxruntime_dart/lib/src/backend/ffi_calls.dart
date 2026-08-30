/// The seam, over `dart:ffi`.
///
/// Thin by construction: the generated wrappers already marshal, check the
/// status and free what they allocated, so most methods here are a pointer
/// conversion around one call. What is written out by hand is what a generator
/// cannot know, which is ownership.
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

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
final class FfiCalls implements OrtCalls {
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

Pointer<T> _as<T extends NativeType>(OrtPtr pointer) =>
    Pointer<T>.fromAddress(pointer.address);

OrtPtr _ptr(Pointer<NativeType> pointer) => OrtPtr(pointer.address);

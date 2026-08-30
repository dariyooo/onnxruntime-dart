/// The boundary between the shared code and a backend.
///
/// One interface, taking Dart types. Each backend marshals in whatever way
/// suits it: the FFI backend with `Arena` and `toNativeUtf8`, the WebAssembly
/// backend by writing into the emscripten heap. Nothing above this line touches
/// bytes, pointer widths or byte order.
///
/// Only genuine runtime handles cross as [OrtPtr]. Everything else, model
/// bytes, tensor data, shapes and names, crosses as Dart values.
///
/// The shape follows the WebAssembly export set, because that is the smaller of
/// the two and an interface either side cannot implement is no use. It is not
/// the ceiling of the public API: calls only native can make live on the FFI
/// backend and are exposed with `@NativeOnly`.
library;

import 'dart:typed_data';

import 'types.dart';

/// The calls both backends can make.
///
/// Failures throw `OrtException`. The C API returns a status that has to be
/// read and released, and the backend does that; nothing above this line sees
/// a status code.
abstract interface class OrtCalls {
  /// Prepares the runtime. Safe to call more than once.
  void init({int loggingLevel});

  /// The version of ONNX Runtime that is loaded, such as `1.29.0`.
  String runtimeVersion();

  OrtPtr createSessionOptions();

  void appendExecutionProvider(
    OrtPtr options,
    String name,
    Map<String, String> configuration,
  );

  void addSessionConfigEntry(OrtPtr options, String key, String value);

  void addFreeDimensionOverride(OrtPtr options, String name, int dimension);

  /// Threads ONNX Runtime may use within a single operator.
  void setIntraOpNumThreads(OrtPtr options, int threads);

  void releaseSessionOptions(OrtPtr options);

  /// Creates a session from a model already in memory.
  ///
  /// Only from bytes. Loading by path would mean `ORTCHAR_T`, which is UTF-16
  /// on Windows, for no gain over reading the file first.
  OrtPtr createSession(Uint8List model, OrtPtr options);

  void releaseSession(OrtPtr session);

  (int inputs, int outputs) inputOutputCount(OrtPtr session);

  OrtTensorMeta inputOutputMetadata(
    OrtPtr session,
    int index, {
    required bool input,
  });

  /// Creates a tensor holding a copy of [data].
  ///
  /// The C call borrows its buffer rather than copying, so the backend owns a
  /// copy for as long as the tensor lives. Keeping that inside the backend is
  /// what stops the most dangerous rule in the C API from reaching the API.
  OrtPtr createTensor(OrtElementType type, TypedData data, List<int> shape);

  /// Creates a string tensor holding [values] in row-major order.
  ///
  /// Strings are stored out of line rather than in `raw_data`, so they cannot
  /// go through [createTensor].
  OrtPtr createStringTensor(List<String> values, List<int> shape);

  /// Reads a tensor's type, shape and contents.
  OrtTensorView tensorData(OrtPtr tensor);

  /// Reads a string tensor's contents in row-major order.
  List<String> stringTensorData(OrtPtr tensor);

  void releaseTensor(OrtPtr tensor);

  OrtPtr createRunOptions();

  void addRunConfigEntry(OrtPtr runOptions, String key, String value);

  void releaseRunOptions(OrtPtr runOptions);

  /// Runs [session], returning one tensor per name in [outputNames].
  ///
  /// The returned tensors are owned by the caller.
  List<OrtPtr> run(
    OrtPtr session,
    Map<String, OrtPtr> inputs,
    List<String> outputNames,
    OrtPtr runOptions,
  );

  OrtPtr createBinding(OrtPtr session);

  void bindInput(OrtPtr binding, String name, OrtPtr tensor);

  void bindOutput(OrtPtr binding, String name, OrtPtr tensor);

  void clearBoundInputs(OrtPtr binding);

  void clearBoundOutputs(OrtPtr binding);

  void runWithBinding(OrtPtr session, OrtPtr binding, OrtPtr runOptions);

  void releaseBinding(OrtPtr binding);

  /// Stops profiling and returns the file it was written to.
  String? endProfiling(OrtPtr session);
}

/// Running a model without blocking the isolate.
///
/// Separate from [OrtCalls] deliberately. The WebAssembly build exports no
/// asynchronous run, and folding this into the seam would either make it
/// unimplementable on the web or force the native side to fake it.
abstract interface class OrtAsyncCalls {
  /// Runs [session], completing with one tensor per name in [outputNames].
  ///
  /// The returned tensors are owned by the caller.
  Future<List<OrtPtr>> runAsync(
    OrtPtr session,
    Map<String, OrtPtr> inputs,
    List<String> outputNames,
    OrtPtr runOptions,
  );
}

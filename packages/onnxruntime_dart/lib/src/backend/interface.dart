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
/// Every method returning `int` returns 0 on success. On anything else call
/// [lastError] for the message.
abstract interface class OrtCalls {
  /// Prepares the runtime. Safe to call more than once.
  int init({int intraOpNumThreads, int loggingLevel});

  /// The message for the most recent failure, or null if there was none.
  String? lastError();

  OrtPtr createSessionOptions();

  int appendExecutionProvider(
    OrtPtr options,
    String name,
    Map<String, String> configuration,
  );

  int addSessionConfigEntry(OrtPtr options, String key, String value);

  int addFreeDimensionOverride(OrtPtr options, String name, int dimension);

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

  /// Reads a tensor's type, shape and contents.
  OrtTensorView tensorData(OrtPtr tensor);

  void releaseTensor(OrtPtr tensor);

  OrtPtr createRunOptions();

  int addRunConfigEntry(OrtPtr runOptions, String key, String value);

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

  int bindInput(OrtPtr binding, String name, OrtPtr tensor);

  int bindOutput(OrtPtr binding, String name, OrtPtr tensor);

  void clearBoundOutputs(OrtPtr binding);

  int runWithBinding(OrtPtr session, OrtPtr binding, OrtPtr runOptions);

  void releaseBinding(OrtPtr binding);

  /// Stops profiling and returns the file it was written to.
  String? endProfiling(OrtPtr session);
}

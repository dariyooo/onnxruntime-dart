/// The boundary between the shared code and a backend.
///
/// Two small interfaces, implemented once over `dart:ffi` and once over the
/// WebAssembly exports. Everything above them is written once and compiles for
/// both.
///
/// The shape follows the WebAssembly export set, because that is the smaller of
/// the two and an interface either side cannot implement is no use. It is not
/// the ceiling of the public API: calls only native can make live on the FFI
/// backend and are exposed with `@NativeOnly`.
library;

import 'dart:typed_data';

import 'types.dart';

/// Allocation in backend memory.
///
/// String marshalling, pointer arrays and dimension arrays are all built on
/// these four operations in shared code. Do not add platform-specific helpers.
abstract interface class OrtMemory {
  /// Allocates [byteCount] bytes, or returns [OrtPtr.nullPtr] on failure.
  OrtPtr allocate(int byteCount);

  /// Releases an allocation from [allocate]. A no-op on [OrtPtr.nullPtr].
  void free(OrtPtr pointer);

  /// Copies [source] into the allocation at [destination].
  void write(OrtPtr destination, TypedData source);

  /// Copies [byteCount] bytes out of the allocation at [source].
  Uint8List read(OrtPtr source, int byteCount);
}

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
    List<String> keys,
    List<String> values,
  );

  int addSessionConfigEntry(OrtPtr options, String key, String value);

  int addFreeDimensionOverride(OrtPtr options, String name, int dimValue);

  void releaseSessionOptions(OrtPtr options);

  /// Creates a session from a model already in memory.
  ///
  /// Only from bytes. Loading by path would mean `ORTCHAR_T`, which is UTF-16 on
  /// Windows, for no gain over reading the file first.
  OrtPtr createSession(OrtPtr modelData, int modelLength, OrtPtr options);

  void releaseSession(OrtPtr session);

  (int inputs, int outputs) inputOutputCount(OrtPtr session);

  OrtTensorMeta inputOutputMetadata(
    OrtPtr session,
    int index, {
    required bool input,
  });

  /// Wraps [data] as a tensor.
  ///
  /// **Borrows [data].** It is not copied, so the allocation must outlive the
  /// tensor. This is the single most dangerous call in the package, which is why
  /// nothing above this interface exposes it directly.
  OrtPtr createTensor(
    OrtElementType type,
    OrtPtr data,
    int dataLength,
    OrtPtr dims,
    int dimsLength,
  );

  OrtTensorView tensorData(OrtPtr tensor);

  void releaseTensor(OrtPtr tensor);

  OrtPtr createRunOptions();

  int addRunConfigEntry(OrtPtr runOptions, String key, String value);

  void releaseRunOptions(OrtPtr runOptions);

  int run(
    OrtPtr session,
    OrtPtr inputIndices,
    OrtPtr inputs,
    int inputCount,
    OrtPtr outputIndices,
    int outputCount,
    OrtPtr outputs,
    OrtPtr runOptions,
  );

  OrtPtr createBinding(OrtPtr session);

  int bindInput(OrtPtr binding, int index, OrtPtr tensor);

  int bindOutput(OrtPtr binding, int index, OrtPtr tensor);

  void clearBoundOutputs(OrtPtr binding);

  int runWithBinding(OrtPtr session, OrtPtr binding, OrtPtr runOptions);

  void releaseBinding(OrtPtr binding);

  /// Stops profiling and returns the file it was written to.
  String? endProfiling(OrtPtr session);
}

/// What a backend provides.
abstract interface class OrtBackend {
  OrtMemory get memory;
  OrtCalls get calls;
}

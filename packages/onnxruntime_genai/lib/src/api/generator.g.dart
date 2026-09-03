// AUTO GENERATED FILE, DO NOT EDIT.
//
// Generated from third_party/onnxruntime-genai/src/ort_genai_c.h.
// Regenerate with `dart run tool/generate_bindings.dart` from this package.

part of 'api.dart';

/// Wraps the `OgaGenerator` handle.
///
/// Above the backend boundary, so it names no pointer type and forwards
/// everything to whichever backend was selected for this platform.
final class Generator extends GenAiHandle {
  Generator._(super.handle);

  @override
  void destroy(GenAiPtr handle) => _calls.destroyGenerator(handle);

  /// Wraps `OgaGenerator_IsDone`.
  bool isDone() => _calls.generatorIsDone(handle);

  /// Wraps `OgaGenerator_IsSessionTerminated`.
  bool isSessionTerminated() => _calls.generatorIsSessionTerminated(handle);

  /// Wraps `OgaGenerator_SetModelInput`.
  void setModelInput(String name, GenAiPtr tensor) => _calls.generatorSetModelInput(handle, name, tensor);

  /// Wraps `OgaGenerator_SetInputs`.
  void setInputs(GenAiPtr namedTensors) => _calls.generatorSetInputs(handle, namedTensors);

  /// Wraps `OgaGenerator_AppendTokenSequences`.
  void appendTokenSequences(GenAiPtr pSequences) => _calls.generatorAppendTokenSequences(handle, pSequences);

  /// Wraps `OgaGenerator_AppendTokens`.
  void appendTokens(List<int> inputIds) => _calls.generatorAppendTokens(handle, inputIds);

  /// Wraps `OgaGenerator_TokenCount`.
  int tokenCount() => _calls.generatorTokenCount(handle);

  /// Wraps `OgaGenerator_GenerateNextToken`.
  void generateNextToken() => _calls.generatorGenerateNextToken(handle);

  /// Wraps `OgaGenerator_SetRuntimeOption`.
  void setRuntimeOption(String key, String value) => _calls.generatorSetRuntimeOption(handle, key, value);

  /// Wraps `OgaGenerator_RewindTo`.
  void rewindTo(int newLength) => _calls.generatorRewindTo(handle, newLength);

  /// Wraps `OgaGenerator_GetInput`.
  Tensor getInput(String name) =>
      Tensor._(_calls.generatorGetInput(handle, name));

  /// Wraps `OgaGenerator_GetOutput`.
  Tensor getOutput(String name) =>
      Tensor._(_calls.generatorGetOutput(handle, name));

  /// Wraps `OgaGenerator_GetLogits`.
  Tensor getLogits() =>
      Tensor._(_calls.generatorGetLogits(handle));

  /// Wraps `OgaGenerator_SetLogits`.
  void setLogits(GenAiPtr tensor) => _calls.generatorSetLogits(handle, tensor);

  /// Wraps `OgaGenerator_GetSequenceCount`.
  int getSequenceCount(int index) => _calls.generatorGetSequenceCount(handle, index);

  /// Wraps `OgaSetActiveAdapter`.
  void setActiveAdapter(GenAiPtr adapters, String adapterName) => _calls.setActiveAdapter(handle, adapters, adapterName);

}

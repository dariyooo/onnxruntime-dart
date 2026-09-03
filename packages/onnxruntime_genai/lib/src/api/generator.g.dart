// AUTO GENERATED FILE, DO NOT EDIT.
//
// Generated from third_party/onnxruntime-genai/src/ort_genai_c.h.
// Regenerate with `dart run tool/generate_bindings.dart` from this package.

part of 'api.dart';

/// Wraps the `OgaGenerator` handle.
final class Generator extends GenAiHandle<OgaGenerator> {
  Generator._(super.handle);

  @override
  void destroy(Pointer<OgaGenerator> handle) => OgaDestroyGenerator(handle);

  /// Wraps `OgaGenerator_IsDone`.
  bool isDone() =>
      OgaGenerator_IsDone(handle);

  /// Wraps `OgaGenerator_IsSessionTerminated`.
  bool isSessionTerminated() =>
      OgaGenerator_IsSessionTerminated(handle);

  /// Wraps `OgaGenerator_SetModelInput`.
  void setModelInput(String name, Tensor tensor) => withArena((arena) {
        check(OgaGenerator_SetModelInput(handle, cString(arena, name), tensor.handle));
      });

  /// Wraps `OgaGenerator_SetInputs`.
  void setInputs(NamedTensors namedTensors) => withArena((arena) {
        check(OgaGenerator_SetInputs(handle, namedTensors.handle));
      });

  /// Wraps `OgaGenerator_AppendTokenSequences`.
  void appendTokenSequences(Sequences pSequences) => withArena((arena) {
        check(OgaGenerator_AppendTokenSequences(handle, pSequences.handle));
      });

  /// Wraps `OgaGenerator_AppendTokens`.
  void appendTokens(List<int> inputIds) => withArena((arena) {
        final inputIdsNative = arena<Int32>(inputIds.length);
        for (var i = 0; i < inputIds.length; i++) {
          inputIdsNative[i] = inputIds[i];
        }
        check(OgaGenerator_AppendTokens(handle, inputIdsNative, inputIds.length));
      });

  /// Wraps `OgaGenerator_TokenCount`.
  int tokenCount() =>
      OgaGenerator_TokenCount(handle);

  /// Wraps `OgaGenerator_GenerateNextToken`.
  void generateNextToken() => withArena((arena) {
        check(OgaGenerator_GenerateNextToken(handle));
      });

  /// Wraps `OgaGenerator_SetRuntimeOption`.
  void setRuntimeOption(String key, String value) => withArena((arena) {
        check(OgaGenerator_SetRuntimeOption(handle, cString(arena, key), cString(arena, value)));
      });

  /// Wraps `OgaGenerator_RewindTo`.
  void rewindTo(int newLength) => withArena((arena) {
        check(OgaGenerator_RewindTo(handle, newLength));
      });

  /// Wraps `OgaGenerator_GetInput`.
  Tensor getInput(String name) => withArena((arena) {
        final out = arena<Pointer<OgaTensor>>();
        check(OgaGenerator_GetInput(handle, cString(arena, name), out));
        return Tensor._(out.value);
      });

  /// Wraps `OgaGenerator_GetOutput`.
  Tensor getOutput(String name) => withArena((arena) {
        final out = arena<Pointer<OgaTensor>>();
        check(OgaGenerator_GetOutput(handle, cString(arena, name), out));
        return Tensor._(out.value);
      });

  /// Wraps `OgaGenerator_GetLogits`.
  Tensor getLogits() => withArena((arena) {
        final out = arena<Pointer<OgaTensor>>();
        check(OgaGenerator_GetLogits(handle, out));
        return Tensor._(out.value);
      });

  /// Wraps `OgaGenerator_SetLogits`.
  void setLogits(Tensor tensor) => withArena((arena) {
        check(OgaGenerator_SetLogits(handle, tensor.handle));
      });

  /// Wraps `OgaGenerator_GetSequenceCount`.
  int getSequenceCount(int index) =>
      withArena((arena) => OgaGenerator_GetSequenceCount(handle, index));

  /// Wraps `OgaSetActiveAdapter`.
  void setActiveAdapter(Adapters adapters, String adapterName) => withArena((arena) {
        check(OgaSetActiveAdapter(handle, adapters.handle, cString(arena, adapterName)));
      });

}

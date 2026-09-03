// AUTO GENERATED FILE, DO NOT EDIT.
//
// Generated from third_party/onnxruntime-genai/src/ort_genai_c.h.
// Regenerate with `dart run tool/generate_bindings.dart` from this package.

part of 'api.dart';

/// Wraps the `OgaMultiModalProcessor` handle.
final class MultiModalProcessor extends GenAiHandle<OgaMultiModalProcessor> {
  MultiModalProcessor._(super.handle);

  @override
  void destroy(Pointer<OgaMultiModalProcessor> handle) => OgaDestroyMultiModalProcessor(handle);

  /// Wraps `OgaProcessorProcessImages`.
  NamedTensors processorProcessImages(String prompt, Images images) => withArena((arena) {
        final out = arena<Pointer<OgaNamedTensors>>();
        check(OgaProcessorProcessImages(handle, cString(arena, prompt), images.handle, out));
        return NamedTensors._(out.value);
      });

  /// Wraps `OgaProcessorProcessImagesAndPrompts`.
  NamedTensors processorProcessImagesAndPrompts(StringArray prompts, Images images) => withArena((arena) {
        final out = arena<Pointer<OgaNamedTensors>>();
        check(OgaProcessorProcessImagesAndPrompts(handle, prompts.handle, images.handle, out));
        return NamedTensors._(out.value);
      });

  /// Wraps `OgaProcessorProcessAudios`.
  NamedTensors processorProcessAudios(String prompt, Audios audios) => withArena((arena) {
        final out = arena<Pointer<OgaNamedTensors>>();
        check(OgaProcessorProcessAudios(handle, cString(arena, prompt), audios.handle, out));
        return NamedTensors._(out.value);
      });

  /// Wraps `OgaProcessorProcessAudiosAndPrompts`.
  NamedTensors processorProcessAudiosAndPrompts(StringArray prompts, Audios audios) => withArena((arena) {
        final out = arena<Pointer<OgaNamedTensors>>();
        check(OgaProcessorProcessAudiosAndPrompts(handle, prompts.handle, audios.handle, out));
        return NamedTensors._(out.value);
      });

  /// Wraps `OgaProcessorProcessImagesAndAudios`.
  NamedTensors processorProcessImagesAndAudios(String prompt, Images images, Audios audios) => withArena((arena) {
        final out = arena<Pointer<OgaNamedTensors>>();
        check(OgaProcessorProcessImagesAndAudios(handle, cString(arena, prompt), images.handle, audios.handle, out));
        return NamedTensors._(out.value);
      });

  /// Wraps `OgaProcessorProcessImagesAndAudiosAndPrompts`.
  NamedTensors processorProcessImagesAndAudiosAndPrompts(StringArray prompts, Images images, Audios audios) => withArena((arena) {
        final out = arena<Pointer<OgaNamedTensors>>();
        check(OgaProcessorProcessImagesAndAudiosAndPrompts(handle, prompts.handle, images.handle, audios.handle, out));
        return NamedTensors._(out.value);
      });

  /// Wraps `OgaProcessorDecode`.
  String processorDecode(List<int> tokens) => withArena((arena) {
        final tokensNative = arena<Int32>(tokens.length);
        for (var i = 0; i < tokens.length; i++) {
          tokensNative[i] = tokens[i];
        }
        final out = arena<Pointer<Char>>();
        check(OgaProcessorDecode(handle, tokensNative, tokens.length, out));
        return borrowedCString(out.value);
      });

  /// Wraps `OgaCreateTokenizerStreamFromProcessor`.
  TokenizerStream createTokenizerStreamFromProcessor() => withArena((arena) {
        final out = arena<Pointer<OgaTokenizerStream>>();
        check(OgaCreateTokenizerStreamFromProcessor(handle, out));
        return TokenizerStream._(out.value);
      });

}

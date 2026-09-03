// AUTO GENERATED FILE, DO NOT EDIT.
//
// Generated from third_party/onnxruntime-genai/src/ort_genai_c.h.
// Regenerate with `dart run tool/generate_bindings.dart` from this package.

part of 'api.dart';

/// Wraps the `OgaMultiModalProcessor` handle.
///
/// Above the backend boundary, so it names no pointer type and forwards
/// everything to whichever backend was selected for this platform.
final class MultiModalProcessor extends GenAiHandle {
  MultiModalProcessor._(super.handle);

  @override
  void destroy(GenAiPtr handle) => _calls.destroyMultiModalProcessor(handle);

  /// Wraps `OgaProcessorProcessImages`.
  NamedTensors processorProcessImages(String prompt, GenAiPtr images) =>
      NamedTensors._(_calls.processorProcessImages(handle, prompt, images));

  /// Wraps `OgaProcessorProcessImagesAndPrompts`.
  NamedTensors processorProcessImagesAndPrompts(
          GenAiPtr prompts, GenAiPtr images) =>
      NamedTensors._(
          _calls.processorProcessImagesAndPrompts(handle, prompts, images));

  /// Wraps `OgaProcessorProcessAudios`.
  NamedTensors processorProcessAudios(String prompt, GenAiPtr audios) =>
      NamedTensors._(_calls.processorProcessAudios(handle, prompt, audios));

  /// Wraps `OgaProcessorProcessAudiosAndPrompts`.
  NamedTensors processorProcessAudiosAndPrompts(
          GenAiPtr prompts, GenAiPtr audios) =>
      NamedTensors._(
          _calls.processorProcessAudiosAndPrompts(handle, prompts, audios));

  /// Wraps `OgaProcessorProcessImagesAndAudios`.
  NamedTensors processorProcessImagesAndAudios(
          String prompt, GenAiPtr images, GenAiPtr audios) =>
      NamedTensors._(_calls.processorProcessImagesAndAudios(
          handle, prompt, images, audios));

  /// Wraps `OgaProcessorProcessImagesAndAudiosAndPrompts`.
  NamedTensors processorProcessImagesAndAudiosAndPrompts(
          GenAiPtr prompts, GenAiPtr images, GenAiPtr audios) =>
      NamedTensors._(_calls.processorProcessImagesAndAudiosAndPrompts(
          handle, prompts, images, audios));

  /// Wraps `OgaProcessorDecode`.
  String processorDecode(List<int> tokens) =>
      _calls.processorDecode(handle, tokens);

  /// Wraps `OgaCreateTokenizerStreamFromProcessor`.
  TokenizerStream createTokenizerStreamFromProcessor() =>
      TokenizerStream._(_calls.createTokenizerStreamFromProcessor(handle));
}

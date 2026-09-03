// AUTO GENERATED FILE, DO NOT EDIT.
//
// Generated from third_party/onnxruntime-genai/src/ort_genai_c.h.
// Regenerate with `dart run tool/generate_bindings.dart` from this package.

import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../bindings/genai_bindings.g.dart';
import 'support.dart';

/// Wraps the `OgaMultiModalProcessor` handle.
final class MultiModalProcessor extends GenAiHandle<OgaMultiModalProcessor> {
  MultiModalProcessor._(super.handle);

  @override
  void destroy(Pointer<OgaMultiModalProcessor> handle) => OgaDestroyMultiModalProcessor(handle);

  /// Wraps `OgaProcessorProcessImages`.
  void processorProcessImages(String prompt, Images images, NamedTensors inputTensors) => withArena((arena) {
        check(OgaProcessorProcessImages(handle, cString(arena, prompt), images.handle, inputTensors.handle));
      });

  /// Wraps `OgaProcessorProcessImagesAndPrompts`.
  void processorProcessImagesAndPrompts(StringArray prompts, Images images, NamedTensors inputTensors) => withArena((arena) {
        check(OgaProcessorProcessImagesAndPrompts(handle, prompts.handle, images.handle, inputTensors.handle));
      });

  /// Wraps `OgaProcessorProcessAudios`.
  void processorProcessAudios(String prompt, Audios audios, NamedTensors inputTensors) => withArena((arena) {
        check(OgaProcessorProcessAudios(handle, cString(arena, prompt), audios.handle, inputTensors.handle));
      });

  /// Wraps `OgaProcessorProcessAudiosAndPrompts`.
  void processorProcessAudiosAndPrompts(StringArray prompts, Audios audios, NamedTensors inputTensors) => withArena((arena) {
        check(OgaProcessorProcessAudiosAndPrompts(handle, prompts.handle, audios.handle, inputTensors.handle));
      });

  /// Wraps `OgaProcessorProcessImagesAndAudios`.
  void processorProcessImagesAndAudios(String prompt, Images images, Audios audios, NamedTensors inputTensors) => withArena((arena) {
        check(OgaProcessorProcessImagesAndAudios(handle, cString(arena, prompt), images.handle, audios.handle, inputTensors.handle));
      });

  /// Wraps `OgaProcessorProcessImagesAndAudiosAndPrompts`.
  void processorProcessImagesAndAudiosAndPrompts(StringArray prompts, Images images, Audios audios, NamedTensors inputTensors) => withArena((arena) {
        check(OgaProcessorProcessImagesAndAudiosAndPrompts(handle, prompts.handle, images.handle, audios.handle, inputTensors.handle));
      });

  /// Wraps `OgaProcessorDecode`.
  String processorDecode(List<int> tokens) => withArena((arena) {
        final out = arena<Pointer<Char>>();
        check(OgaProcessorDecode(handle, tokensNative, tokens.length, out));
        return takeCString(out.value);
      });

  /// Wraps `OgaCreateTokenizerStreamFromProcessor`.
  TokenizerStream createTokenizerStreamFromProcessor() => withArena((arena) {
        final out = arena<Pointer<OgaTokenizerStream>>();
        check(OgaCreateTokenizerStreamFromProcessor(handle, out));
        return TokenizerStream._(out.value);
      });

}

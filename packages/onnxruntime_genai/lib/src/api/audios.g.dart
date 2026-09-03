// AUTO GENERATED FILE, DO NOT EDIT.
//
// Generated from third_party/onnxruntime-genai/src/ort_genai_c.h.
// Regenerate with `dart run tool/generate_bindings.dart` from this package.

part of 'api.dart';

/// Wraps the `OgaAudios` handle.
///
/// Above the backend boundary, so it names no pointer type and forwards
/// everything to whichever backend was selected for this platform.
final class Audios extends GenAiHandle {
  Audios._(super.handle);

  @override
  void destroy(GenAiPtr handle) => _calls.destroyAudios(handle);

  /// Wraps `OgaLoadAudio`.
  factory Audios.loadAudio(String audioPath) =>
      Audios._(_calls.loadAudio(audioPath));

}

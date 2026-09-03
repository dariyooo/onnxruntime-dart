// AUTO GENERATED FILE, DO NOT EDIT.
//
// Generated from third_party/onnxruntime-genai/src/ort_genai_c.h.
// Regenerate with `dart run tool/generate_bindings.dart` from this package.

part of 'api.dart';

/// Wraps the `OgaAudios` handle.
final class Audios extends GenAiHandle<OgaAudios> {
  Audios._(super.handle);

  @override
  void destroy(Pointer<OgaAudios> handle) => OgaDestroyAudios(handle);

}

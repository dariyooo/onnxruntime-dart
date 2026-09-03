// AUTO GENERATED FILE, DO NOT EDIT.
//
// Generated from third_party/onnxruntime-genai/src/ort_genai_c.h.
// Regenerate with `dart run tool/generate_bindings.dart` from this package.

part of 'api.dart';

/// Wraps the `OgaImages` handle.
final class Images extends GenAiHandle<OgaImages> {
  Images._(super.handle);

  @override
  void destroy(Pointer<OgaImages> handle) => OgaDestroyImages(handle);

}

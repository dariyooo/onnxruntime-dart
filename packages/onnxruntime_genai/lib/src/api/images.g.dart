// AUTO GENERATED FILE, DO NOT EDIT.
//
// Generated from third_party/onnxruntime-genai/src/ort_genai_c.h.
// Regenerate with `dart run tool/generate_bindings.dart` from this package.

part of 'api.dart';

/// Wraps the `OgaImages` handle.
///
/// Above the backend boundary, so it names no pointer type and forwards
/// everything to whichever backend was selected for this platform.
final class Images extends GenAiHandle {
  Images._(super.handle);

  @override
  void destroy(GenAiPtr handle) => _calls.destroyImages(handle);

  /// Wraps `OgaLoadImage`.
  factory Images.loadImage(String imagePath) =>
      Images._(_calls.loadImage(imagePath));

  /// Wraps `OgaLoadImagesFromBuffers`.
  factory Images.loadImagesFromBuffers(List<Uint8List> imageData) =>
      Images._(_calls.loadImagesFromBuffers(imageData));
}

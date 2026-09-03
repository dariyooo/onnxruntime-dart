// AUTO GENERATED FILE, DO NOT EDIT.
//
// Generated from third_party/onnxruntime-genai/src/ort_genai_c.h.
// Regenerate with `dart run tool/generate_bindings.dart` from this package.

part of 'api.dart';

/// Wraps the `OgaTensor` handle.
///
/// Above the backend boundary, so it names no pointer type and forwards
/// everything to whichever backend was selected for this platform.
final class Tensor extends GenAiHandle {
  Tensor._(super.handle);

  @override
  void destroy(GenAiPtr handle) => _calls.destroyTensor(handle);

  /// Wraps `OgaTensorGetType`.
  int getType() => _calls.tensorGetType(handle);

  /// Wraps `OgaTensorGetShapeRank`.
  int getShapeRank() => _calls.tensorGetShapeRank(handle);

  /// Wraps `OgaTensorGetShape`.
  void getShape(List<int> shapeDims) =>
      _calls.tensorGetShape(handle, shapeDims);
}

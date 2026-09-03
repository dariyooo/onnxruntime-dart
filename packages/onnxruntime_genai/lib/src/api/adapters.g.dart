// AUTO GENERATED FILE, DO NOT EDIT.
//
// Generated from third_party/onnxruntime-genai/src/ort_genai_c.h.
// Regenerate with `dart run tool/generate_bindings.dart` from this package.

part of 'api.dart';

/// Wraps the `OgaAdapters` handle.
///
/// Above the backend boundary, so it names no pointer type and forwards
/// everything to whichever backend was selected for this platform.
final class Adapters extends GenAiHandle {
  Adapters._(super.handle);

  @override
  void destroy(GenAiPtr handle) => _calls.destroyAdapters(handle);

  /// Wraps `OgaLoadAdapter`.
  void loadAdapter(String adapterFilePath, String adapterName) =>
      _calls.loadAdapter(handle, adapterFilePath, adapterName);

  /// Wraps `OgaUnloadAdapter`.
  void unloadAdapter(String adapterName) =>
      _calls.unloadAdapter(handle, adapterName);
}

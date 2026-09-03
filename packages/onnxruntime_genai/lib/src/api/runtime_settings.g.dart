// AUTO GENERATED FILE, DO NOT EDIT.
//
// Generated from third_party/onnxruntime-genai/src/ort_genai_c.h.
// Regenerate with `dart run tool/generate_bindings.dart` from this package.

part of 'api.dart';

/// Wraps the `OgaRuntimeSettings` handle.
///
/// Above the backend boundary, so it names no pointer type and forwards
/// everything to whichever backend was selected for this platform.
final class RuntimeSettings extends GenAiHandle {
  RuntimeSettings._(super.handle);

  @override
  void destroy(GenAiPtr handle) => _calls.destroyRuntimeSettings(handle);

  /// Wraps `OgaCreateRuntimeSettings`.
  factory RuntimeSettings() =>
      RuntimeSettings._(_calls.createRuntimeSettings());

  /// Wraps `OgaCreateModelWithRuntimeSettings`.
  Model createModelWithRuntimeSettings(String configPath) =>
      Model._(_calls.createModelWithRuntimeSettings(handle, configPath));

}

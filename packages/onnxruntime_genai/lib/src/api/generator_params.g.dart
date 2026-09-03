// AUTO GENERATED FILE, DO NOT EDIT.
//
// Generated from third_party/onnxruntime-genai/src/ort_genai_c.h.
// Regenerate with `dart run tool/generate_bindings.dart` from this package.

part of 'api.dart';

/// Wraps the `OgaGeneratorParams` handle.
///
/// Above the backend boundary, so it names no pointer type and forwards
/// everything to whichever backend was selected for this platform.
final class GeneratorParams extends GenAiHandle {
  GeneratorParams._(super.handle);

  @override
  void destroy(GenAiPtr handle) => _calls.destroyGeneratorParams(handle);

  /// Wraps `OgaGeneratorParamsSetSearchNumber`.
  void setSearchNumber(String name, double value) =>
      _calls.generatorParamsSetSearchNumber(handle, name, value);

  /// Wraps `OgaGeneratorParamsSetSearchBool`.
  void setSearchBool(String name, bool value) =>
      _calls.generatorParamsSetSearchBool(handle, name, value);

  /// Wraps `OgaGeneratorParamsSetGuidance`.
  void setGuidance(String type, String data, bool enableFfTokens) =>
      _calls.generatorParamsSetGuidance(handle, type, data, enableFfTokens);

  /// Wraps `OgaGeneratorParamsGetSearchNumber`.
  double getSearchNumber(String name) =>
      _calls.generatorParamsGetSearchNumber(handle, name);

  /// Wraps `OgaGeneratorParamsGetSearchBool`.
  bool getSearchBool(String name) =>
      _calls.generatorParamsGetSearchBool(handle, name);

  /// Wraps `OgaCreateRequest`.
  Request createRequest() => Request._(_calls.createRequest(handle));
}

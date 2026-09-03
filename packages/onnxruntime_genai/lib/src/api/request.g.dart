// AUTO GENERATED FILE, DO NOT EDIT.
//
// Generated from third_party/onnxruntime-genai/src/ort_genai_c.h.
// Regenerate with `dart run tool/generate_bindings.dart` from this package.

part of 'api.dart';

/// Wraps the `OgaRequest` handle.
///
/// Above the backend boundary, so it names no pointer type and forwards
/// everything to whichever backend was selected for this platform.
final class Request extends GenAiHandle {
  Request._(super.handle);

  @override
  void destroy(GenAiPtr handle) => _calls.destroyRequest(handle);

  /// Wraps `OgaRequestAddTokens`.
  void addTokens(GenAiPtr tokens) => _calls.requestAddTokens(handle, tokens);

  /// Wraps `OgaRequestHasUnseenTokens`.
  bool hasUnseenTokens() => _calls.requestHasUnseenTokens(handle);

  /// Wraps `OgaRequestGetUnseenToken`.
  int getUnseenToken() => _calls.requestGetUnseenToken(handle);

  /// Wraps `OgaRequestIsDone`.
  bool isDone() => _calls.requestIsDone(handle);
}

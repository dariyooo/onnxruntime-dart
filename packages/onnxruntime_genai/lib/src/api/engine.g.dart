// AUTO GENERATED FILE, DO NOT EDIT.
//
// Generated from third_party/onnxruntime-genai/src/ort_genai_c.h.
// Regenerate with `dart run tool/generate_bindings.dart` from this package.

part of 'api.dart';

/// Wraps the `OgaEngine` handle.
///
/// Above the backend boundary, so it names no pointer type and forwards
/// everything to whichever backend was selected for this platform.
final class Engine extends GenAiHandle {
  Engine._(super.handle);

  @override
  void destroy(GenAiPtr handle) => _calls.destroyEngine(handle);

  /// Wraps `OgaEngineStep`.
  Request step() => Request._(_calls.engineStep(handle));

  /// Wraps `OgaEngineHasPendingRequests`.
  bool hasPendingRequests() => _calls.engineHasPendingRequests(handle);

  /// Wraps `OgaEngineAddRequest`.
  ///
  /// Keeps the buffer it is given rather than copying it, so that
  /// memory must outlive the handle. It is the caller's to allocate
  /// and to free, and freeing it first leaves the handle pointing
  /// at nothing.
  void addRequest(GenAiPtr request) => _calls.engineAddRequest(handle, request);

  /// Wraps `OgaEngineRemoveRequest`.
  void removeRequest(GenAiPtr request) =>
      _calls.engineRemoveRequest(handle, request);
}

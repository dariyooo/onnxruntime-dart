// AUTO GENERATED FILE, DO NOT EDIT.
//
// Generated from third_party/onnxruntime-genai/src/ort_genai_c.h.
// Regenerate with `dart run tool/generate_bindings.dart` from this package.

part of 'api.dart';

/// Wraps the `OgaTokenizerStream` handle.
///
/// Above the backend boundary, so it names no pointer type and forwards
/// everything to whichever backend was selected for this platform.
final class TokenizerStream extends GenAiHandle {
  TokenizerStream._(super.handle);

  @override
  void destroy(GenAiPtr handle) => _calls.destroyTokenizerStream(handle);

  /// Wraps `OgaTokenizerStreamDecode`.
  String decode(int token) => _calls.tokenizerStreamDecode(handle, token);

}

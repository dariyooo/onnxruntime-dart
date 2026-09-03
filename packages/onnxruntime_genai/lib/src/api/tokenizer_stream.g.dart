// AUTO GENERATED FILE, DO NOT EDIT.
//
// Generated from third_party/onnxruntime-genai/src/ort_genai_c.h.
// Regenerate with `dart run tool/generate_bindings.dart` from this package.

part of 'api.dart';

/// Wraps the `OgaTokenizerStream` handle.
final class TokenizerStream extends GenAiHandle<OgaTokenizerStream> {
  TokenizerStream._(super.handle);

  @override
  void destroy(Pointer<OgaTokenizerStream> handle) => OgaDestroyTokenizerStream(handle);

  /// Wraps `OgaTokenizerStreamDecode`.
  String decode(int token) => withArena((arena) {
        final out = arena<Pointer<Char>>();
        check(OgaTokenizerStreamDecode(handle, token, out));
        return borrowedCString(out.value);
      });

}

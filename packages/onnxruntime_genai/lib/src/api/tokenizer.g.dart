// AUTO GENERATED FILE, DO NOT EDIT.
//
// Generated from third_party/onnxruntime-genai/src/ort_genai_c.h.
// Regenerate with `dart run tool/generate_bindings.dart` from this package.

part of 'api.dart';

/// Wraps the `OgaTokenizer` handle.
final class Tokenizer extends GenAiHandle<OgaTokenizer> {
  Tokenizer._(super.handle);

  @override
  void destroy(Pointer<OgaTokenizer> handle) => OgaDestroyTokenizer(handle);

  /// Wraps `OgaTokenizerEncode`.
  void encode(String str, Sequences sequences) => withArena((arena) {
        check(OgaTokenizerEncode(handle, cString(arena, str), sequences.handle));
      });

  /// Wraps `OgaTokenizerDecodeBatch`.
  StringArray decodeBatch(Tensor tensor) => withArena((arena) {
        final out = arena<Pointer<OgaStringArray>>();
        check(OgaTokenizerDecodeBatch(handle, tensor.handle, out));
        return StringArray._(out.value);
      });

  /// Wraps `OgaTokenizerDecode`.
  String decode(List<int> tokens) => withArena((arena) {
        final tokensNative = arena<Int32>(tokens.length);
        for (var i = 0; i < tokens.length; i++) {
          tokensNative[i] = tokens[i];
        }
        final out = arena<Pointer<Char>>();
        check(OgaTokenizerDecode(handle, tokensNative, tokens.length, out));
        return takeCString(out.value);
      });

  /// Wraps `OgaTokenizerApplyChatTemplate`.
  String applyChatTemplate(String templateStr, String messages, String tools, bool addGenerationPrompt) => withArena((arena) {
        final out = arena<Pointer<Char>>();
        check(OgaTokenizerApplyChatTemplate(handle, cString(arena, templateStr), cString(arena, messages), cString(arena, tools), addGenerationPrompt, out));
        return takeCString(out.value);
      });

  /// Wraps `OgaCreateTokenizerStream`.
  TokenizerStream createTokenizerStream() => withArena((arena) {
        final out = arena<Pointer<OgaTokenizerStream>>();
        check(OgaCreateTokenizerStream(handle, out));
        return TokenizerStream._(out.value);
      });

}

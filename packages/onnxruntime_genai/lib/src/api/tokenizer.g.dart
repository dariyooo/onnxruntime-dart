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

  /// Wraps `OgaTokenizerGetBosTokenId`.
  int getBosTokenId() => withArena((arena) {
        final out = arena<Int32>();
        check(OgaTokenizerGetBosTokenId(handle, out));
        return out.value;
      });

  /// Wraps `OgaTokenizerGetPadTokenId`.
  int getPadTokenId() => withArena((arena) {
        final out = arena<Int32>();
        check(OgaTokenizerGetPadTokenId(handle, out));
        return out.value;
      });

  /// Wraps `OgaTokenizerGetBotTokenId`.
  int getBotTokenId() => withArena((arena) {
        final out = arena<Int32>();
        check(OgaTokenizerGetBotTokenId(handle, out));
        return out.value;
      });

  /// Wraps `OgaTokenizerGetEotTokenId`.
  int getEotTokenId() => withArena((arena) {
        final out = arena<Int32>();
        check(OgaTokenizerGetEotTokenId(handle, out));
        return out.value;
      });

  /// Wraps `OgaTokenizerGetBorTokenId`.
  int getBorTokenId() => withArena((arena) {
        final out = arena<Int32>();
        check(OgaTokenizerGetBorTokenId(handle, out));
        return out.value;
      });

  /// Wraps `OgaTokenizerGetEorTokenId`.
  int getEorTokenId() => withArena((arena) {
        final out = arena<Int32>();
        check(OgaTokenizerGetEorTokenId(handle, out));
        return out.value;
      });

  /// Wraps `OgaTokenizerEncode`.
  void encode(String str, Sequences sequences) => withArena((arena) {
        check(OgaTokenizerEncode(handle, cString(arena, str), sequences.handle));
      });

  /// Wraps `OgaTokenizerEncodeBatch`.
  Tensor encodeBatch(List<String> strings) => withArena((arena) {
        final stringsNative = arena<Pointer<Char>>(strings.length);
        for (var i = 0; i < strings.length; i++) {
          stringsNative[i] = cString(arena, strings[i]);
        }
        final out = arena<Pointer<OgaTensor>>();
        check(OgaTokenizerEncodeBatch(handle, stringsNative, strings.length, out));
        return Tensor._(out.value);
      });

  /// Wraps `OgaTokenizerDecodeBatch`.
  StringArray decodeBatch(Tensor tensor) => withArena((arena) {
        final out = arena<Pointer<OgaStringArray>>();
        check(OgaTokenizerDecodeBatch(handle, tensor.handle, out));
        return StringArray._(out.value);
      });

  /// Wraps `OgaTokenizerToTokenId`.
  int toTokenId(String str) => withArena((arena) {
        final out = arena<Int32>();
        check(OgaTokenizerToTokenId(handle, cString(arena, str), out));
        return out.value;
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

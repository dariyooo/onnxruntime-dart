// AUTO GENERATED FILE, DO NOT EDIT.
//
// Generated from third_party/onnxruntime-genai/src/ort_genai_c.h.
// Regenerate with `dart run tool/generate_bindings.dart` from this package.

part of 'api.dart';

/// Wraps the `OgaTokenizer` handle.
///
/// Above the backend boundary, so it names no pointer type and forwards
/// everything to whichever backend was selected for this platform.
final class Tokenizer extends GenAiHandle {
  Tokenizer._(super.handle);

  @override
  void destroy(GenAiPtr handle) => _calls.destroyTokenizer(handle);

  /// Wraps `OgaUpdateTokenizerOptions`.
  void updateTokenizerOptions(Map<String, String> options) =>
      _calls.updateTokenizerOptions(handle, options);

  /// Wraps `OgaTokenizerGetBosTokenId`.
  int getBosTokenId() => _calls.tokenizerGetBosTokenId(handle);

  /// Wraps `OgaTokenizerGetEosTokenIds`.
  List<int> getEosTokenIds() => _calls.tokenizerGetEosTokenIds(handle);

  /// Wraps `OgaTokenizerGetPadTokenId`.
  int getPadTokenId() => _calls.tokenizerGetPadTokenId(handle);

  /// Wraps `OgaTokenizerGetBotTokenId`.
  int getBotTokenId() => _calls.tokenizerGetBotTokenId(handle);

  /// Wraps `OgaTokenizerGetEotTokenId`.
  int getEotTokenId() => _calls.tokenizerGetEotTokenId(handle);

  /// Wraps `OgaTokenizerGetBorTokenId`.
  int getBorTokenId() => _calls.tokenizerGetBorTokenId(handle);

  /// Wraps `OgaTokenizerGetEorTokenId`.
  int getEorTokenId() => _calls.tokenizerGetEorTokenId(handle);

  /// Wraps `OgaTokenizerEncode`.
  void encode(String str, GenAiPtr sequences) =>
      _calls.tokenizerEncode(handle, str, sequences);

  /// Wraps `OgaTokenizerEncodeBatch`.
  Tensor encodeBatch(List<String> strings) =>
      Tensor._(_calls.tokenizerEncodeBatch(handle, strings));

  /// Wraps `OgaTokenizerDecodeBatch`.
  StringArray decodeBatch(GenAiPtr tensor) =>
      StringArray._(_calls.tokenizerDecodeBatch(handle, tensor));

  /// Wraps `OgaTokenizerToTokenId`.
  int toTokenId(String str) => _calls.tokenizerToTokenId(handle, str);

  /// Wraps `OgaTokenizerDecode`.
  String decode(List<int> tokens) => _calls.tokenizerDecode(handle, tokens);

  /// Wraps `OgaTokenizerApplyChatTemplate`.
  String applyChatTemplate(String templateStr, String messages, String tools,
          bool addGenerationPrompt) =>
      _calls.tokenizerApplyChatTemplate(
          handle, templateStr, messages, tools, addGenerationPrompt);

  /// Wraps `OgaCreateTokenizerStream`.
  TokenizerStream createTokenizerStream() =>
      TokenizerStream._(_calls.createTokenizerStream(handle));
}

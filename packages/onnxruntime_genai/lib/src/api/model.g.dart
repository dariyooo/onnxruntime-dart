// AUTO GENERATED FILE, DO NOT EDIT.
//
// Generated from third_party/onnxruntime-genai/src/ort_genai_c.h.
// Regenerate with `dart run tool/generate_bindings.dart` from this package.

part of 'api.dart';

/// Wraps the `OgaModel` handle.
///
/// Above the backend boundary, so it names no pointer type and forwards
/// everything to whichever backend was selected for this platform.
final class Model extends GenAiHandle {
  Model._(super.handle);

  @override
  void destroy(GenAiPtr handle) => _calls.destroyModel(handle);

  /// Wraps `OgaCreateModel`.
  factory Model(String configPath) => Model._(_calls.createModel(configPath));

  /// Wraps `OgaModelGetType`.
  String getType() => _calls.modelGetType(handle);

  /// Wraps `OgaModelGetDeviceType`.
  String getDeviceType() => _calls.modelGetDeviceType(handle);

  /// Wraps `OgaCreateGeneratorParams`.
  GeneratorParams createGeneratorParams() =>
      GeneratorParams._(_calls.createGeneratorParams(handle));

  /// Wraps `OgaCreateGenerator`.
  Generator createGenerator(GenAiPtr params) =>
      Generator._(_calls.createGenerator(handle, params));

  /// Wraps `OgaCreateTokenizer`.
  Tokenizer createTokenizer() => Tokenizer._(_calls.createTokenizer(handle));

  /// Wraps `OgaCreateMultiModalProcessor`.
  MultiModalProcessor createMultiModalProcessor() =>
      MultiModalProcessor._(_calls.createMultiModalProcessor(handle));

  /// Wraps `OgaCreateAdapters`.
  Adapters createAdapters() => Adapters._(_calls.createAdapters(handle));

  /// Wraps `OgaCreateEngine`.
  Engine createEngine() => Engine._(_calls.createEngine(handle));

  /// Wraps `OgaCreateStreamingProcessor`.
  StreamingProcessor createStreamingProcessor() =>
      StreamingProcessor._(_calls.createStreamingProcessor(handle));
}

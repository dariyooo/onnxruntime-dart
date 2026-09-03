// AUTO GENERATED FILE, DO NOT EDIT.
//
// Generated from third_party/onnxruntime-genai/src/ort_genai_c.h.
// Regenerate with `dart run tool/generate_bindings.dart` from this package.

part of 'api.dart';

/// Wraps the `OgaModel` handle.
final class Model extends GenAiHandle<OgaModel> {
  Model._(super.handle);

  @override
  void destroy(Pointer<OgaModel> handle) => OgaDestroyModel(handle);

  /// Wraps `OgaCreateModel`.
  factory Model(String configPath) => withArena((arena) {
        final out = arena<Pointer<OgaModel>>();
        check(OgaCreateModel(cString(arena, configPath), out));
        return Model._(out.value);
      });

  /// Wraps `OgaModelGetType`.
  String getType() => withArena((arena) {
        final out = arena<Pointer<Char>>();
        check(OgaModelGetType(handle, out));
        return takeCString(out.value);
      });

  /// Wraps `OgaModelGetDeviceType`.
  String getDeviceType() => withArena((arena) {
        final out = arena<Pointer<Char>>();
        check(OgaModelGetDeviceType(handle, out));
        return takeCString(out.value);
      });

  /// Wraps `OgaCreateGeneratorParams`.
  GeneratorParams createGeneratorParams() => withArena((arena) {
        final out = arena<Pointer<OgaGeneratorParams>>();
        check(OgaCreateGeneratorParams(handle, out));
        return GeneratorParams._(out.value);
      });

  /// Wraps `OgaCreateGenerator`.
  Generator createGenerator(GeneratorParams params) => withArena((arena) {
        final out = arena<Pointer<OgaGenerator>>();
        check(OgaCreateGenerator(handle, params.handle, out));
        return Generator._(out.value);
      });

  /// Wraps `OgaCreateTokenizer`.
  Tokenizer createTokenizer() => withArena((arena) {
        final out = arena<Pointer<OgaTokenizer>>();
        check(OgaCreateTokenizer(handle, out));
        return Tokenizer._(out.value);
      });

  /// Wraps `OgaCreateMultiModalProcessor`.
  MultiModalProcessor createMultiModalProcessor() => withArena((arena) {
        final out = arena<Pointer<OgaMultiModalProcessor>>();
        check(OgaCreateMultiModalProcessor(handle, out));
        return MultiModalProcessor._(out.value);
      });

  /// Wraps `OgaCreateAdapters`.
  Adapters createAdapters() => withArena((arena) {
        final out = arena<Pointer<OgaAdapters>>();
        check(OgaCreateAdapters(handle, out));
        return Adapters._(out.value);
      });

  /// Wraps `OgaCreateEngine`.
  Engine createEngine() => withArena((arena) {
        final out = arena<Pointer<OgaEngine>>();
        check(OgaCreateEngine(handle, out));
        return Engine._(out.value);
      });

  /// Wraps `OgaCreateStreamingProcessor`.
  StreamingProcessor createStreamingProcessor() => withArena((arena) {
        final out = arena<Pointer<OgaStreamingProcessor>>();
        check(OgaCreateStreamingProcessor(handle, out));
        return StreamingProcessor._(out.value);
      });

}

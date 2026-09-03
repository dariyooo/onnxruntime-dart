// AUTO GENERATED FILE, DO NOT EDIT.
//
// Generated from third_party/onnxruntime-genai/src/ort_genai_c.h.
// Regenerate with `dart run tool/generate_bindings.dart` from this package.

/// The native backend.
///
/// The only generated file that is native. It marshals Dart values into the
/// arena, forwards to the generated bindings, and turns a failed `OgaResult`
/// into a [GenAiException].
library;

import 'dart:ffi';
import 'dart:typed_data';

import '../bindings/genai_bindings.g.dart';
import 'ffi_support.dart';
import 'interface.dart';
import 'types.dart';

/// The backend for this platform.
GenAiCalls createCalls() => FfiGenAiCalls();

/// GenAI reached through `dart:ffi`.
final class FfiGenAiCalls implements GenAiCalls {
  @override
  void shutdown() => withArena((arena) {
        OgaShutdown();
      });

  @override
  void setTelemetryEnabled(bool enabled) => withArena((arena) {
        OgaSetTelemetryEnabled(enabled);
      });

  @override
  void setLogBool(String name, bool value) => withArena((arena) {
        check(OgaSetLogBool(cString(arena, name), value));
      });

  @override
  void setLogString(String name, String value) => withArena((arena) {
        check(OgaSetLogString(cString(arena, name), cString(arena, value)));
      });

  @override
  void destroyString(String value) => withArena((arena) {
        OgaDestroyString(cString(arena, value));
      });

  @override
  void setCurrentGpuDeviceId(int deviceId) => withArena((arena) {
        check(OgaSetCurrentGpuDeviceId(deviceId));
      });

  @override
  int getCurrentGpuDeviceId() => withArena((arena) {
        final out = arena<Int>();
        check(OgaGetCurrentGpuDeviceId(out));
        return out.value;
      });

  @override
  void registerExecutionProviderLibrary(
          String registrationName, String libraryPath) =>
      withArena((arena) {
        OgaRegisterExecutionProviderLibrary(
            cString(arena, registrationName), cString(arena, libraryPath));
      });

  @override
  void unregisterExecutionProviderLibrary(String registrationName) =>
      withArena((arena) {
        OgaUnregisterExecutionProviderLibrary(cString(arena, registrationName));
      });

  @override
  void destroyNamedTensors(GenAiPtr handle) =>
      OgaDestroyNamedTensors(pointer<OgaNamedTensors>(handle));

  @override
  GenAiPtr createNamedTensors() => withArena((arena) {
        final out = arena<Pointer<OgaNamedTensors>>();
        check(OgaCreateNamedTensors(out));
        return handleOf(out.value);
      });

  @override
  GenAiPtr namedTensorsGet(GenAiPtr handle, String name) => withArena((arena) {
        final out = arena<Pointer<OgaTensor>>();
        check(OgaNamedTensorsGet(
            pointer<OgaNamedTensors>(handle), cString(arena, name), out));
        return handleOf(out.value);
      });

  @override
  void namedTensorsSet(GenAiPtr handle, String name, GenAiPtr tensor) =>
      withArena((arena) {
        check(OgaNamedTensorsSet(pointer<OgaNamedTensors>(handle),
            cString(arena, name), pointer<OgaTensor>(tensor)));
      });

  @override
  void namedTensorsDelete(GenAiPtr handle, String name) => withArena((arena) {
        check(OgaNamedTensorsDelete(
            pointer<OgaNamedTensors>(handle), cString(arena, name)));
      });

  @override
  int namedTensorsCount(GenAiPtr handle) => withArena((arena) {
        final out = arena<Size>();
        check(OgaNamedTensorsCount(pointer<OgaNamedTensors>(handle), out));
        return out.value;
      });

  @override
  GenAiPtr namedTensorsGetNames(GenAiPtr handle) => withArena((arena) {
        final out = arena<Pointer<OgaStringArray>>();
        check(OgaNamedTensorsGetNames(pointer<OgaNamedTensors>(handle), out));
        return handleOf(out.value);
      });

  @override
  void destroySequences(GenAiPtr handle) =>
      OgaDestroySequences(pointer<OgaSequences>(handle));

  @override
  GenAiPtr createSequences() => withArena((arena) {
        final out = arena<Pointer<OgaSequences>>();
        check(OgaCreateSequences(out));
        return handleOf(out.value);
      });

  @override
  int sequencesCount(GenAiPtr handle) => withArena((arena) {
        return OgaSequencesCount(pointer<OgaSequences>(handle));
      });

  @override
  void appendTokenSequence(GenAiPtr handle, List<int> tokenPtr) =>
      withArena((arena) {
        final tokenPtrNative = arena<Int32>(tokenPtr.length);
        for (var i = 0; i < tokenPtr.length; i++) {
          tokenPtrNative[i] = tokenPtr[i];
        }
        check(OgaAppendTokenSequence(
            tokenPtrNative, tokenPtr.length, pointer<OgaSequences>(handle)));
      });

  @override
  void appendTokenToSequence(GenAiPtr handle, int token, int sequenceIndex) =>
      withArena((arena) {
        check(OgaAppendTokenToSequence(
            token, pointer<OgaSequences>(handle), sequenceIndex));
      });

  @override
  int sequencesGetSequenceCount(GenAiPtr handle, int sequenceIndex) =>
      withArena((arena) {
        return OgaSequencesGetSequenceCount(
            pointer<OgaSequences>(handle), sequenceIndex);
      });

  @override
  List<int> sequencesGetSequenceData(GenAiPtr handle, int sequenceIndex) =>
      withArena((arena) {
        final length = OgaSequencesGetSequenceCount(
            pointer<OgaSequences>(handle), sequenceIndex);
        final data = OgaSequencesGetSequenceData(
            pointer<OgaSequences>(handle), sequenceIndex);
        return List<int>.generate(length, (i) => data[i]);
      });

  @override
  void destroyImages(GenAiPtr handle) =>
      OgaDestroyImages(pointer<OgaImages>(handle));

  @override
  void destroyStringArray(GenAiPtr handle) =>
      OgaDestroyStringArray(pointer<OgaStringArray>(handle));

  @override
  GenAiPtr loadImages(GenAiPtr handle) => withArena((arena) {
        final out = arena<Pointer<OgaImages>>();
        check(OgaLoadImages(pointer<OgaStringArray>(handle), out));
        return handleOf(out.value);
      });

  @override
  GenAiPtr loadAudios(GenAiPtr handle) => withArena((arena) {
        final out = arena<Pointer<OgaAudios>>();
        check(OgaLoadAudios(pointer<OgaStringArray>(handle), out));
        return handleOf(out.value);
      });

  @override
  GenAiPtr createStringArray() => withArena((arena) {
        final out = arena<Pointer<OgaStringArray>>();
        check(OgaCreateStringArray(out));
        return handleOf(out.value);
      });

  @override
  void stringArrayAddString(GenAiPtr handle, String str) => withArena((arena) {
        check(OgaStringArrayAddString(
            pointer<OgaStringArray>(handle), cString(arena, str)));
      });

  @override
  int stringArrayGetCount(GenAiPtr handle) => withArena((arena) {
        final out = arena<Size>();
        check(OgaStringArrayGetCount(pointer<OgaStringArray>(handle), out));
        return out.value;
      });

  @override
  String stringArrayGetString(GenAiPtr handle, int index) => withArena((arena) {
        final out = arena<Pointer<Char>>();
        check(OgaStringArrayGetString(
            pointer<OgaStringArray>(handle), index, out));
        return borrowedCString(out.value);
      });

  @override
  void destroyAudios(GenAiPtr handle) =>
      OgaDestroyAudios(pointer<OgaAudios>(handle));

  @override
  void destroyRuntimeSettings(GenAiPtr handle) =>
      OgaDestroyRuntimeSettings(pointer<OgaRuntimeSettings>(handle));

  @override
  GenAiPtr createRuntimeSettings() => withArena((arena) {
        final out = arena<Pointer<OgaRuntimeSettings>>();
        check(OgaCreateRuntimeSettings(out));
        return handleOf(out.value);
      });

  @override
  GenAiPtr createModelWithRuntimeSettings(GenAiPtr handle, String configPath) =>
      withArena((arena) {
        final out = arena<Pointer<OgaModel>>();
        check(OgaCreateModelWithRuntimeSettings(cString(arena, configPath),
            pointer<OgaRuntimeSettings>(handle), out));
        return handleOf(out.value);
      });

  @override
  void destroyConfig(GenAiPtr handle) =>
      OgaDestroyConfig(pointer<OgaConfig>(handle));

  @override
  GenAiPtr createConfig(String configPath) => withArena((arena) {
        final out = arena<Pointer<OgaConfig>>();
        check(OgaCreateConfig(cString(arena, configPath), out));
        return handleOf(out.value);
      });

  @override
  GenAiPtr createConfigFromPackageEp(String configPath, String ep) =>
      withArena((arena) {
        final out = arena<Pointer<OgaConfig>>();
        check(OgaCreateConfigFromPackageEp(
            cString(arena, configPath), cString(arena, ep), out));
        return handleOf(out.value);
      });

  @override
  void configClearProviders(GenAiPtr handle) => withArena((arena) {
        check(OgaConfigClearProviders(pointer<OgaConfig>(handle)));
      });

  @override
  void configAppendProvider(GenAiPtr handle, String provider) =>
      withArena((arena) {
        check(OgaConfigAppendProvider(
            pointer<OgaConfig>(handle), cString(arena, provider)));
      });

  @override
  void configSetProviderOption(
          GenAiPtr handle, String provider, String key, String value) =>
      withArena((arena) {
        check(OgaConfigSetProviderOption(
            pointer<OgaConfig>(handle),
            cString(arena, provider),
            cString(arena, key),
            cString(arena, value)));
      });

  @override
  void configAddModelData(
          GenAiPtr handle, String modelFilename, Uint8List modelData) =>
      withArena((arena) {
        final modelDataNative = arena<Uint8>(modelData.length);
        for (var i = 0; i < modelData.length; i++) {
          modelDataNative[i] = modelData[i];
        }
        check(OgaConfigAddModelData(
            pointer<OgaConfig>(handle),
            cString(arena, modelFilename),
            modelDataNative.cast(),
            modelData.length));
      });

  @override
  void configRemoveModelData(GenAiPtr handle, String modelFilename) =>
      withArena((arena) {
        check(OgaConfigRemoveModelData(
            pointer<OgaConfig>(handle), cString(arena, modelFilename)));
      });

  @override
  void configSetDecoderProviderOptionsHardwareDeviceType(
          GenAiPtr handle, String provider, String hardwareDeviceType) =>
      withArena((arena) {
        check(OgaConfigSetDecoderProviderOptionsHardwareDeviceType(
            pointer<OgaConfig>(handle),
            cString(arena, provider),
            cString(arena, hardwareDeviceType)));
      });

  @override
  void configSetDecoderProviderOptionsHardwareDeviceId(
          GenAiPtr handle, String provider, int hardwareDeviceId) =>
      withArena((arena) {
        check(OgaConfigSetDecoderProviderOptionsHardwareDeviceId(
            pointer<OgaConfig>(handle),
            cString(arena, provider),
            hardwareDeviceId));
      });

  @override
  void configSetDecoderProviderOptionsHardwareVendorId(
          GenAiPtr handle, String provider, int hardwareVendorId) =>
      withArena((arena) {
        check(OgaConfigSetDecoderProviderOptionsHardwareVendorId(
            pointer<OgaConfig>(handle),
            cString(arena, provider),
            hardwareVendorId));
      });

  @override
  void configClearDecoderProviderOptionsHardwareDeviceType(
          GenAiPtr handle, String provider) =>
      withArena((arena) {
        check(OgaConfigClearDecoderProviderOptionsHardwareDeviceType(
            pointer<OgaConfig>(handle), cString(arena, provider)));
      });

  @override
  void configClearDecoderProviderOptionsHardwareDeviceId(
          GenAiPtr handle, String provider) =>
      withArena((arena) {
        check(OgaConfigClearDecoderProviderOptionsHardwareDeviceId(
            pointer<OgaConfig>(handle), cString(arena, provider)));
      });

  @override
  void configClearDecoderProviderOptionsHardwareVendorId(
          GenAiPtr handle, String provider) =>
      withArena((arena) {
        check(OgaConfigClearDecoderProviderOptionsHardwareVendorId(
            pointer<OgaConfig>(handle), cString(arena, provider)));
      });

  @override
  void configOverlay(GenAiPtr handle, String json) => withArena((arena) {
        check(
            OgaConfigOverlay(pointer<OgaConfig>(handle), cString(arena, json)));
      });

  @override
  GenAiPtr createModelFromConfig(GenAiPtr handle) => withArena((arena) {
        final out = arena<Pointer<OgaModel>>();
        check(OgaCreateModelFromConfig(pointer<OgaConfig>(handle), out));
        return handleOf(out.value);
      });

  @override
  void destroyModel(GenAiPtr handle) =>
      OgaDestroyModel(pointer<OgaModel>(handle));

  @override
  GenAiPtr createModel(String configPath) => withArena((arena) {
        final out = arena<Pointer<OgaModel>>();
        check(OgaCreateModel(cString(arena, configPath), out));
        return handleOf(out.value);
      });

  @override
  String modelGetType(GenAiPtr handle) => withArena((arena) {
        final out = arena<Pointer<Char>>();
        check(OgaModelGetType(pointer<OgaModel>(handle), out));
        return takeCString(out.value);
      });

  @override
  String modelGetDeviceType(GenAiPtr handle) => withArena((arena) {
        final out = arena<Pointer<Char>>();
        check(OgaModelGetDeviceType(pointer<OgaModel>(handle), out));
        return takeCString(out.value);
      });

  @override
  GenAiPtr createGeneratorParams(GenAiPtr handle) => withArena((arena) {
        final out = arena<Pointer<OgaGeneratorParams>>();
        check(OgaCreateGeneratorParams(pointer<OgaModel>(handle), out));
        return handleOf(out.value);
      });

  @override
  GenAiPtr createGenerator(GenAiPtr handle, GenAiPtr params) =>
      withArena((arena) {
        final out = arena<Pointer<OgaGenerator>>();
        check(OgaCreateGenerator(pointer<OgaModel>(handle),
            pointer<OgaGeneratorParams>(params), out));
        return handleOf(out.value);
      });

  @override
  GenAiPtr createTokenizer(GenAiPtr handle) => withArena((arena) {
        final out = arena<Pointer<OgaTokenizer>>();
        check(OgaCreateTokenizer(pointer<OgaModel>(handle), out));
        return handleOf(out.value);
      });

  @override
  GenAiPtr createMultiModalProcessor(GenAiPtr handle) => withArena((arena) {
        final out = arena<Pointer<OgaMultiModalProcessor>>();
        check(OgaCreateMultiModalProcessor(pointer<OgaModel>(handle), out));
        return handleOf(out.value);
      });

  @override
  GenAiPtr createAdapters(GenAiPtr handle) => withArena((arena) {
        final out = arena<Pointer<OgaAdapters>>();
        check(OgaCreateAdapters(pointer<OgaModel>(handle), out));
        return handleOf(out.value);
      });

  @override
  GenAiPtr createEngine(GenAiPtr handle) => withArena((arena) {
        final out = arena<Pointer<OgaEngine>>();
        check(OgaCreateEngine(pointer<OgaModel>(handle), out));
        return handleOf(out.value);
      });

  @override
  GenAiPtr createStreamingProcessor(GenAiPtr handle) => withArena((arena) {
        final out = arena<Pointer<OgaStreamingProcessor>>();
        check(OgaCreateStreamingProcessor(pointer<OgaModel>(handle), out));
        return handleOf(out.value);
      });

  @override
  void destroyGeneratorParams(GenAiPtr handle) =>
      OgaDestroyGeneratorParams(pointer<OgaGeneratorParams>(handle));

  @override
  void generatorParamsSetSearchNumber(
          GenAiPtr handle, String name, double value) =>
      withArena((arena) {
        check(OgaGeneratorParamsSetSearchNumber(
            pointer<OgaGeneratorParams>(handle), cString(arena, name), value));
      });

  @override
  void generatorParamsSetSearchBool(GenAiPtr handle, String name, bool value) =>
      withArena((arena) {
        check(OgaGeneratorParamsSetSearchBool(
            pointer<OgaGeneratorParams>(handle), cString(arena, name), value));
      });

  @override
  void generatorParamsSetGuidance(
          GenAiPtr handle, String type, String data, bool enableFfTokens) =>
      withArena((arena) {
        check(OgaGeneratorParamsSetGuidance(pointer<OgaGeneratorParams>(handle),
            cString(arena, type), cString(arena, data), enableFfTokens));
      });

  @override
  double generatorParamsGetSearchNumber(GenAiPtr handle, String name) =>
      withArena((arena) {
        final out = arena<Double>();
        check(OgaGeneratorParamsGetSearchNumber(
            pointer<OgaGeneratorParams>(handle), cString(arena, name), out));
        return out.value;
      });

  @override
  bool generatorParamsGetSearchBool(GenAiPtr handle, String name) =>
      withArena((arena) {
        final out = arena<Bool>();
        check(OgaGeneratorParamsGetSearchBool(
            pointer<OgaGeneratorParams>(handle), cString(arena, name), out));
        return out.value;
      });

  @override
  GenAiPtr createRequest(GenAiPtr handle) => withArena((arena) {
        final out = arena<Pointer<OgaRequest>>();
        check(OgaCreateRequest(pointer<OgaGeneratorParams>(handle), out));
        return handleOf(out.value);
      });

  @override
  void destroyGenerator(GenAiPtr handle) =>
      OgaDestroyGenerator(pointer<OgaGenerator>(handle));

  @override
  bool generatorIsDone(GenAiPtr handle) => withArena((arena) {
        return OgaGenerator_IsDone(pointer<OgaGenerator>(handle));
      });

  @override
  bool generatorIsSessionTerminated(GenAiPtr handle) => withArena((arena) {
        return OgaGenerator_IsSessionTerminated(pointer<OgaGenerator>(handle));
      });

  @override
  void generatorSetModelInput(GenAiPtr handle, String name, GenAiPtr tensor) =>
      withArena((arena) {
        check(OgaGenerator_SetModelInput(pointer<OgaGenerator>(handle),
            cString(arena, name), pointer<OgaTensor>(tensor)));
      });

  @override
  void generatorSetInputs(GenAiPtr handle, GenAiPtr namedTensors) =>
      withArena((arena) {
        check(OgaGenerator_SetInputs(pointer<OgaGenerator>(handle),
            pointer<OgaNamedTensors>(namedTensors)));
      });

  @override
  void generatorAppendTokenSequences(GenAiPtr handle, GenAiPtr pSequences) =>
      withArena((arena) {
        check(OgaGenerator_AppendTokenSequences(
            pointer<OgaGenerator>(handle), pointer<OgaSequences>(pSequences)));
      });

  @override
  void generatorAppendTokens(GenAiPtr handle, List<int> inputIds) =>
      withArena((arena) {
        final inputIdsNative = arena<Int32>(inputIds.length);
        for (var i = 0; i < inputIds.length; i++) {
          inputIdsNative[i] = inputIds[i];
        }
        check(OgaGenerator_AppendTokens(
            pointer<OgaGenerator>(handle), inputIdsNative, inputIds.length));
      });

  @override
  int generatorTokenCount(GenAiPtr handle) => withArena((arena) {
        return OgaGenerator_TokenCount(pointer<OgaGenerator>(handle));
      });

  @override
  void generatorGenerateNextToken(GenAiPtr handle) => withArena((arena) {
        check(OgaGenerator_GenerateNextToken(pointer<OgaGenerator>(handle)));
      });

  @override
  void generatorSetRuntimeOption(GenAiPtr handle, String key, String value) =>
      withArena((arena) {
        check(OgaGenerator_SetRuntimeOption(pointer<OgaGenerator>(handle),
            cString(arena, key), cString(arena, value)));
      });

  @override
  void generatorRewindTo(GenAiPtr handle, int newLength) => withArena((arena) {
        check(OgaGenerator_RewindTo(pointer<OgaGenerator>(handle), newLength));
      });

  @override
  GenAiPtr generatorGetInput(GenAiPtr handle, String name) =>
      withArena((arena) {
        final out = arena<Pointer<OgaTensor>>();
        check(OgaGenerator_GetInput(
            pointer<OgaGenerator>(handle), cString(arena, name), out));
        return handleOf(out.value);
      });

  @override
  GenAiPtr generatorGetOutput(GenAiPtr handle, String name) =>
      withArena((arena) {
        final out = arena<Pointer<OgaTensor>>();
        check(OgaGenerator_GetOutput(
            pointer<OgaGenerator>(handle), cString(arena, name), out));
        return handleOf(out.value);
      });

  @override
  GenAiPtr generatorGetLogits(GenAiPtr handle) => withArena((arena) {
        final out = arena<Pointer<OgaTensor>>();
        check(OgaGenerator_GetLogits(pointer<OgaGenerator>(handle), out));
        return handleOf(out.value);
      });

  @override
  void generatorSetLogits(GenAiPtr handle, GenAiPtr tensor) =>
      withArena((arena) {
        check(OgaGenerator_SetLogits(
            pointer<OgaGenerator>(handle), pointer<OgaTensor>(tensor)));
      });

  @override
  int generatorGetSequenceCount(GenAiPtr handle, int index) =>
      withArena((arena) {
        return OgaGenerator_GetSequenceCount(
            pointer<OgaGenerator>(handle), index);
      });

  @override
  List<int> generatorGetSequenceData(GenAiPtr handle, int index) =>
      withArena((arena) {
        final length =
            OgaGenerator_GetSequenceCount(pointer<OgaGenerator>(handle), index);
        final data =
            OgaGenerator_GetSequenceData(pointer<OgaGenerator>(handle), index);
        return List<int>.generate(length, (i) => data[i]);
      });

  @override
  void setActiveAdapter(
          GenAiPtr handle, GenAiPtr adapters, String adapterName) =>
      withArena((arena) {
        check(OgaSetActiveAdapter(pointer<OgaGenerator>(handle),
            pointer<OgaAdapters>(adapters), cString(arena, adapterName)));
      });

  @override
  void destroyTokenizer(GenAiPtr handle) =>
      OgaDestroyTokenizer(pointer<OgaTokenizer>(handle));

  @override
  int tokenizerGetBosTokenId(GenAiPtr handle) => withArena((arena) {
        final out = arena<Int32>();
        check(OgaTokenizerGetBosTokenId(pointer<OgaTokenizer>(handle), out));
        return out.value;
      });

  @override
  int tokenizerGetPadTokenId(GenAiPtr handle) => withArena((arena) {
        final out = arena<Int32>();
        check(OgaTokenizerGetPadTokenId(pointer<OgaTokenizer>(handle), out));
        return out.value;
      });

  @override
  int tokenizerGetBotTokenId(GenAiPtr handle) => withArena((arena) {
        final out = arena<Int32>();
        check(OgaTokenizerGetBotTokenId(pointer<OgaTokenizer>(handle), out));
        return out.value;
      });

  @override
  int tokenizerGetEotTokenId(GenAiPtr handle) => withArena((arena) {
        final out = arena<Int32>();
        check(OgaTokenizerGetEotTokenId(pointer<OgaTokenizer>(handle), out));
        return out.value;
      });

  @override
  int tokenizerGetBorTokenId(GenAiPtr handle) => withArena((arena) {
        final out = arena<Int32>();
        check(OgaTokenizerGetBorTokenId(pointer<OgaTokenizer>(handle), out));
        return out.value;
      });

  @override
  int tokenizerGetEorTokenId(GenAiPtr handle) => withArena((arena) {
        final out = arena<Int32>();
        check(OgaTokenizerGetEorTokenId(pointer<OgaTokenizer>(handle), out));
        return out.value;
      });

  @override
  void tokenizerEncode(GenAiPtr handle, String str, GenAiPtr sequences) =>
      withArena((arena) {
        check(OgaTokenizerEncode(pointer<OgaTokenizer>(handle),
            cString(arena, str), pointer<OgaSequences>(sequences)));
      });

  @override
  GenAiPtr tokenizerEncodeBatch(GenAiPtr handle, List<String> strings) =>
      withArena((arena) {
        final stringsNative = arena<Pointer<Char>>(strings.length);
        for (var i = 0; i < strings.length; i++) {
          stringsNative[i] = cString(arena, strings[i]);
        }
        final out = arena<Pointer<OgaTensor>>();
        check(OgaTokenizerEncodeBatch(
            pointer<OgaTokenizer>(handle), stringsNative, strings.length, out));
        return handleOf(out.value);
      });

  @override
  GenAiPtr tokenizerDecodeBatch(GenAiPtr handle, GenAiPtr tensor) =>
      withArena((arena) {
        final out = arena<Pointer<OgaStringArray>>();
        check(OgaTokenizerDecodeBatch(
            pointer<OgaTokenizer>(handle), pointer<OgaTensor>(tensor), out));
        return handleOf(out.value);
      });

  @override
  int tokenizerToTokenId(GenAiPtr handle, String str) => withArena((arena) {
        final out = arena<Int32>();
        check(OgaTokenizerToTokenId(
            pointer<OgaTokenizer>(handle), cString(arena, str), out));
        return out.value;
      });

  @override
  String tokenizerDecode(GenAiPtr handle, List<int> tokens) =>
      withArena((arena) {
        final tokensNative = arena<Int32>(tokens.length);
        for (var i = 0; i < tokens.length; i++) {
          tokensNative[i] = tokens[i];
        }
        final out = arena<Pointer<Char>>();
        check(OgaTokenizerDecode(
            pointer<OgaTokenizer>(handle), tokensNative, tokens.length, out));
        return takeCString(out.value);
      });

  @override
  String tokenizerApplyChatTemplate(GenAiPtr handle, String templateStr,
          String messages, String tools, bool addGenerationPrompt) =>
      withArena((arena) {
        final out = arena<Pointer<Char>>();
        check(OgaTokenizerApplyChatTemplate(
            pointer<OgaTokenizer>(handle),
            cString(arena, templateStr),
            cString(arena, messages),
            cString(arena, tools),
            addGenerationPrompt,
            out));
        return takeCString(out.value);
      });

  @override
  GenAiPtr createTokenizerStream(GenAiPtr handle) => withArena((arena) {
        final out = arena<Pointer<OgaTokenizerStream>>();
        check(OgaCreateTokenizerStream(pointer<OgaTokenizer>(handle), out));
        return handleOf(out.value);
      });

  @override
  void destroyMultiModalProcessor(GenAiPtr handle) =>
      OgaDestroyMultiModalProcessor(pointer<OgaMultiModalProcessor>(handle));

  @override
  GenAiPtr processorProcessImages(
          GenAiPtr handle, String prompt, GenAiPtr images) =>
      withArena((arena) {
        final out = arena<Pointer<OgaNamedTensors>>();
        check(OgaProcessorProcessImages(pointer<OgaMultiModalProcessor>(handle),
            cString(arena, prompt), pointer<OgaImages>(images), out));
        return handleOf(out.value);
      });

  @override
  GenAiPtr processorProcessImagesAndPrompts(
          GenAiPtr handle, GenAiPtr prompts, GenAiPtr images) =>
      withArena((arena) {
        final out = arena<Pointer<OgaNamedTensors>>();
        check(OgaProcessorProcessImagesAndPrompts(
            pointer<OgaMultiModalProcessor>(handle),
            pointer<OgaStringArray>(prompts),
            pointer<OgaImages>(images),
            out));
        return handleOf(out.value);
      });

  @override
  GenAiPtr processorProcessAudios(
          GenAiPtr handle, String prompt, GenAiPtr audios) =>
      withArena((arena) {
        final out = arena<Pointer<OgaNamedTensors>>();
        check(OgaProcessorProcessAudios(pointer<OgaMultiModalProcessor>(handle),
            cString(arena, prompt), pointer<OgaAudios>(audios), out));
        return handleOf(out.value);
      });

  @override
  GenAiPtr processorProcessAudiosAndPrompts(
          GenAiPtr handle, GenAiPtr prompts, GenAiPtr audios) =>
      withArena((arena) {
        final out = arena<Pointer<OgaNamedTensors>>();
        check(OgaProcessorProcessAudiosAndPrompts(
            pointer<OgaMultiModalProcessor>(handle),
            pointer<OgaStringArray>(prompts),
            pointer<OgaAudios>(audios),
            out));
        return handleOf(out.value);
      });

  @override
  GenAiPtr processorProcessImagesAndAudios(
          GenAiPtr handle, String prompt, GenAiPtr images, GenAiPtr audios) =>
      withArena((arena) {
        final out = arena<Pointer<OgaNamedTensors>>();
        check(OgaProcessorProcessImagesAndAudios(
            pointer<OgaMultiModalProcessor>(handle),
            cString(arena, prompt),
            pointer<OgaImages>(images),
            pointer<OgaAudios>(audios),
            out));
        return handleOf(out.value);
      });

  @override
  GenAiPtr processorProcessImagesAndAudiosAndPrompts(GenAiPtr handle,
          GenAiPtr prompts, GenAiPtr images, GenAiPtr audios) =>
      withArena((arena) {
        final out = arena<Pointer<OgaNamedTensors>>();
        check(OgaProcessorProcessImagesAndAudiosAndPrompts(
            pointer<OgaMultiModalProcessor>(handle),
            pointer<OgaStringArray>(prompts),
            pointer<OgaImages>(images),
            pointer<OgaAudios>(audios),
            out));
        return handleOf(out.value);
      });

  @override
  String processorDecode(GenAiPtr handle, List<int> tokens) =>
      withArena((arena) {
        final tokensNative = arena<Int32>(tokens.length);
        for (var i = 0; i < tokens.length; i++) {
          tokensNative[i] = tokens[i];
        }
        final out = arena<Pointer<Char>>();
        check(OgaProcessorDecode(pointer<OgaMultiModalProcessor>(handle),
            tokensNative, tokens.length, out));
        return borrowedCString(out.value);
      });

  @override
  GenAiPtr createTokenizerStreamFromProcessor(GenAiPtr handle) =>
      withArena((arena) {
        final out = arena<Pointer<OgaTokenizerStream>>();
        check(OgaCreateTokenizerStreamFromProcessor(
            pointer<OgaMultiModalProcessor>(handle), out));
        return handleOf(out.value);
      });

  @override
  void destroyTokenizerStream(GenAiPtr handle) =>
      OgaDestroyTokenizerStream(pointer<OgaTokenizerStream>(handle));

  @override
  String tokenizerStreamDecode(GenAiPtr handle, int token) =>
      withArena((arena) {
        final out = arena<Pointer<Char>>();
        check(OgaTokenizerStreamDecode(
            pointer<OgaTokenizerStream>(handle), token, out));
        return borrowedCString(out.value);
      });

  @override
  void destroyTensor(GenAiPtr handle) =>
      OgaDestroyTensor(pointer<OgaTensor>(handle));

  @override
  int tensorGetShapeRank(GenAiPtr handle) => withArena((arena) {
        final out = arena<Size>();
        check(OgaTensorGetShapeRank(pointer<OgaTensor>(handle), out));
        return out.value;
      });

  @override
  void tensorGetShape(GenAiPtr handle, List<int> shapeDims) =>
      withArena((arena) {
        final shapeDimsNative = arena<Int64>(shapeDims.length);
        for (var i = 0; i < shapeDims.length; i++) {
          shapeDimsNative[i] = shapeDims[i];
        }
        check(OgaTensorGetShape(
            pointer<OgaTensor>(handle), shapeDimsNative, shapeDims.length));
      });

  @override
  void destroyAdapters(GenAiPtr handle) =>
      OgaDestroyAdapters(pointer<OgaAdapters>(handle));

  @override
  void loadAdapter(
          GenAiPtr handle, String adapterFilePath, String adapterName) =>
      withArena((arena) {
        check(OgaLoadAdapter(pointer<OgaAdapters>(handle),
            cString(arena, adapterFilePath), cString(arena, adapterName)));
      });

  @override
  void unloadAdapter(GenAiPtr handle, String adapterName) => withArena((arena) {
        check(OgaUnloadAdapter(
            pointer<OgaAdapters>(handle), cString(arena, adapterName)));
      });

  @override
  void destroyEngine(GenAiPtr handle) =>
      OgaDestroyEngine(pointer<OgaEngine>(handle));

  @override
  GenAiPtr engineStep(GenAiPtr handle) => withArena((arena) {
        final out = arena<Pointer<OgaRequest>>();
        check(OgaEngineStep(pointer<OgaEngine>(handle), out));
        return handleOf(out.value);
      });

  @override
  bool engineHasPendingRequests(GenAiPtr handle) => withArena((arena) {
        final out = arena<Bool>();
        check(OgaEngineHasPendingRequests(pointer<OgaEngine>(handle), out));
        return out.value;
      });

  @override
  void engineAddRequest(GenAiPtr handle, GenAiPtr request) =>
      withArena((arena) {
        check(OgaEngineAddRequest(
            pointer<OgaEngine>(handle), pointer<OgaRequest>(request)));
      });

  @override
  void engineRemoveRequest(GenAiPtr handle, GenAiPtr request) =>
      withArena((arena) {
        check(OgaEngineRemoveRequest(
            pointer<OgaEngine>(handle), pointer<OgaRequest>(request)));
      });

  @override
  void destroyRequest(GenAiPtr handle) =>
      OgaDestroyRequest(pointer<OgaRequest>(handle));

  @override
  void requestAddTokens(GenAiPtr handle, GenAiPtr tokens) => withArena((arena) {
        check(OgaRequestAddTokens(
            pointer<OgaRequest>(handle), pointer<OgaSequences>(tokens)));
      });

  @override
  bool requestHasUnseenTokens(GenAiPtr handle) => withArena((arena) {
        final out = arena<Bool>();
        check(OgaRequestHasUnseenTokens(pointer<OgaRequest>(handle), out));
        return out.value;
      });

  @override
  int requestGetUnseenToken(GenAiPtr handle) => withArena((arena) {
        final out = arena<Int32>();
        check(OgaRequestGetUnseenToken(pointer<OgaRequest>(handle), out));
        return out.value;
      });

  @override
  bool requestIsDone(GenAiPtr handle) => withArena((arena) {
        final out = arena<Bool>();
        check(OgaRequestIsDone(pointer<OgaRequest>(handle), out));
        return out.value;
      });

  @override
  void destroyStreamingProcessor(GenAiPtr handle) =>
      OgaDestroyStreamingProcessor(pointer<OgaStreamingProcessor>(handle));

  @override
  GenAiPtr streamingProcessorProcess(GenAiPtr handle, List<double> audioData) =>
      withArena((arena) {
        final audioDataNative = arena<Float>(audioData.length);
        for (var i = 0; i < audioData.length; i++) {
          audioDataNative[i] = audioData[i];
        }
        final out = arena<Pointer<OgaNamedTensors>>();
        check(OgaStreamingProcessorProcess(
            pointer<OgaStreamingProcessor>(handle),
            audioDataNative,
            audioData.length,
            out));
        return handleOf(out.value);
      });

  @override
  GenAiPtr streamingProcessorFlush(GenAiPtr handle) => withArena((arena) {
        final out = arena<Pointer<OgaNamedTensors>>();
        check(OgaStreamingProcessorFlush(
            pointer<OgaStreamingProcessor>(handle), out));
        return handleOf(out.value);
      });

  @override
  void streamingProcessorSetOption(GenAiPtr handle, String key, String value) =>
      withArena((arena) {
        check(OgaStreamingProcessorSetOption(
            pointer<OgaStreamingProcessor>(handle),
            cString(arena, key),
            cString(arena, value)));
      });

  @override
  String streamingProcessorGetOption(GenAiPtr handle, String key) =>
      withArena((arena) {
        final out = arena<Pointer<Char>>();
        check(OgaStreamingProcessorGetOption(
            pointer<OgaStreamingProcessor>(handle), cString(arena, key), out));
        return takeCString(out.value);
      });
}

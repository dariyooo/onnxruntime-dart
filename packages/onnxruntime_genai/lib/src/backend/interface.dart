// AUTO GENERATED FILE, DO NOT EDIT.
//
// Generated from third_party/onnxruntime-genai/src/ort_genai_c.h.
// Regenerate with `dart run tool/generate_bindings.dart` from this package.

/// The boundary between the shared code and a backend.
///
/// One interface, taking Dart types and [GenAiPtr]. Nothing here mentions
/// `dart:ffi`, so everything above this line compiles for the web as well as
/// for native. Only handles cross as [GenAiPtr]; everything else crosses as a
/// Dart value.
library;

import 'dart:typed_data';

import 'types.dart';

/// The calls a backend has to be able to make.
///
/// Failures throw [GenAiException]. The C API reports them by returning a
/// result object that has to be read and released, and the backend does that;
/// nothing above this line sees one.
abstract interface class GenAiCalls {
  /// Wraps `OgaShutdown`.
  void shutdown();

  /// Wraps `OgaSetTelemetryEnabled`.
  void setTelemetryEnabled(bool enabled);

  /// Wraps `OgaSetLogBool`.
  void setLogBool(String name, bool value);

  /// Wraps `OgaSetLogString`.
  void setLogString(String name, String value);

  /// Wraps `OgaDestroyString`.
  void destroyString(String value);

  /// Wraps `OgaSetCurrentGpuDeviceId`.
  void setCurrentGpuDeviceId(int deviceId);

  /// Wraps `OgaGetCurrentGpuDeviceId`.
  int getCurrentGpuDeviceId();

  /// Wraps `OgaRegisterExecutionProviderLibrary`.
  void registerExecutionProviderLibrary(
      String registrationName, String libraryPath);

  /// Wraps `OgaUnregisterExecutionProviderLibrary`.
  void unregisterExecutionProviderLibrary(String registrationName);

  /// Wraps `OgaDestroyNamedTensors`.
  void destroyNamedTensors(GenAiPtr handle);

  /// Wraps `OgaCreateNamedTensors`.
  GenAiPtr createNamedTensors();

  /// Wraps `OgaNamedTensorsGet`.
  GenAiPtr namedTensorsGet(GenAiPtr handle, String name);

  /// Wraps `OgaNamedTensorsSet`.
  void namedTensorsSet(GenAiPtr handle, String name, GenAiPtr tensor);

  /// Wraps `OgaNamedTensorsDelete`.
  void namedTensorsDelete(GenAiPtr handle, String name);

  /// Wraps `OgaNamedTensorsCount`.
  int namedTensorsCount(GenAiPtr handle);

  /// Wraps `OgaNamedTensorsGetNames`.
  GenAiPtr namedTensorsGetNames(GenAiPtr handle);

  /// Wraps `OgaDestroySequences`.
  void destroySequences(GenAiPtr handle);

  /// Wraps `OgaCreateSequences`.
  GenAiPtr createSequences();

  /// Wraps `OgaSequencesCount`.
  int sequencesCount(GenAiPtr handle);

  /// Wraps `OgaAppendTokenSequence`.
  void appendTokenSequence(GenAiPtr handle, List<int> tokenPtr);

  /// Wraps `OgaAppendTokenToSequence`.
  void appendTokenToSequence(GenAiPtr handle, int token, int sequenceIndex);

  /// Wraps `OgaSequencesGetSequenceCount`.
  int sequencesGetSequenceCount(GenAiPtr handle, int sequenceIndex);

  /// Wraps `OgaSequencesGetSequenceData`.
  List<int> sequencesGetSequenceData(GenAiPtr handle, int sequenceIndex);

  /// Wraps `OgaDestroyImages`.
  void destroyImages(GenAiPtr handle);

  /// Wraps `OgaDestroyStringArray`.
  void destroyStringArray(GenAiPtr handle);

  /// Wraps `OgaLoadImages`.
  GenAiPtr loadImages(GenAiPtr handle);

  /// Wraps `OgaLoadAudios`.
  GenAiPtr loadAudios(GenAiPtr handle);

  /// Wraps `OgaCreateStringArray`.
  GenAiPtr createStringArray();

  /// Wraps `OgaStringArrayAddString`.
  void stringArrayAddString(GenAiPtr handle, String str);

  /// Wraps `OgaStringArrayGetCount`.
  int stringArrayGetCount(GenAiPtr handle);

  /// Wraps `OgaStringArrayGetString`.
  String stringArrayGetString(GenAiPtr handle, int index);

  /// Wraps `OgaDestroyAudios`.
  void destroyAudios(GenAiPtr handle);

  /// Wraps `OgaDestroyRuntimeSettings`.
  void destroyRuntimeSettings(GenAiPtr handle);

  /// Wraps `OgaCreateRuntimeSettings`.
  GenAiPtr createRuntimeSettings();

  /// Wraps `OgaCreateModelWithRuntimeSettings`.
  GenAiPtr createModelWithRuntimeSettings(GenAiPtr handle, String configPath);

  /// Wraps `OgaDestroyConfig`.
  void destroyConfig(GenAiPtr handle);

  /// Wraps `OgaCreateConfig`.
  GenAiPtr createConfig(String configPath);

  /// Wraps `OgaCreateConfigFromPackageEp`.
  GenAiPtr createConfigFromPackageEp(String configPath, String ep);

  /// Wraps `OgaConfigClearProviders`.
  void configClearProviders(GenAiPtr handle);

  /// Wraps `OgaConfigAppendProvider`.
  void configAppendProvider(GenAiPtr handle, String provider);

  /// Wraps `OgaConfigSetProviderOption`.
  void configSetProviderOption(
      GenAiPtr handle, String provider, String key, String value);

  /// Wraps `OgaConfigAddModelData`.
  void configAddModelData(
      GenAiPtr handle, String modelFilename, Uint8List modelData);

  /// Wraps `OgaConfigRemoveModelData`.
  void configRemoveModelData(GenAiPtr handle, String modelFilename);

  /// Wraps `OgaConfigSetDecoderProviderOptionsHardwareDeviceType`.
  void configSetDecoderProviderOptionsHardwareDeviceType(
      GenAiPtr handle, String provider, String hardwareDeviceType);

  /// Wraps `OgaConfigSetDecoderProviderOptionsHardwareDeviceId`.
  void configSetDecoderProviderOptionsHardwareDeviceId(
      GenAiPtr handle, String provider, int hardwareDeviceId);

  /// Wraps `OgaConfigSetDecoderProviderOptionsHardwareVendorId`.
  void configSetDecoderProviderOptionsHardwareVendorId(
      GenAiPtr handle, String provider, int hardwareVendorId);

  /// Wraps `OgaConfigClearDecoderProviderOptionsHardwareDeviceType`.
  void configClearDecoderProviderOptionsHardwareDeviceType(
      GenAiPtr handle, String provider);

  /// Wraps `OgaConfigClearDecoderProviderOptionsHardwareDeviceId`.
  void configClearDecoderProviderOptionsHardwareDeviceId(
      GenAiPtr handle, String provider);

  /// Wraps `OgaConfigClearDecoderProviderOptionsHardwareVendorId`.
  void configClearDecoderProviderOptionsHardwareVendorId(
      GenAiPtr handle, String provider);

  /// Wraps `OgaConfigOverlay`.
  void configOverlay(GenAiPtr handle, String json);

  /// Wraps `OgaCreateModelFromConfig`.
  GenAiPtr createModelFromConfig(GenAiPtr handle);

  /// Wraps `OgaDestroyModel`.
  void destroyModel(GenAiPtr handle);

  /// Wraps `OgaCreateModel`.
  GenAiPtr createModel(String configPath);

  /// Wraps `OgaModelGetType`.
  String modelGetType(GenAiPtr handle);

  /// Wraps `OgaModelGetDeviceType`.
  String modelGetDeviceType(GenAiPtr handle);

  /// Wraps `OgaCreateGeneratorParams`.
  GenAiPtr createGeneratorParams(GenAiPtr handle);

  /// Wraps `OgaCreateGenerator`.
  GenAiPtr createGenerator(GenAiPtr handle, GenAiPtr params);

  /// Wraps `OgaCreateTokenizer`.
  GenAiPtr createTokenizer(GenAiPtr handle);

  /// Wraps `OgaCreateMultiModalProcessor`.
  GenAiPtr createMultiModalProcessor(GenAiPtr handle);

  /// Wraps `OgaCreateAdapters`.
  GenAiPtr createAdapters(GenAiPtr handle);

  /// Wraps `OgaCreateEngine`.
  GenAiPtr createEngine(GenAiPtr handle);

  /// Wraps `OgaCreateStreamingProcessor`.
  GenAiPtr createStreamingProcessor(GenAiPtr handle);

  /// Wraps `OgaDestroyGeneratorParams`.
  void destroyGeneratorParams(GenAiPtr handle);

  /// Wraps `OgaGeneratorParamsSetSearchNumber`.
  void generatorParamsSetSearchNumber(
      GenAiPtr handle, String name, double value);

  /// Wraps `OgaGeneratorParamsSetSearchBool`.
  void generatorParamsSetSearchBool(GenAiPtr handle, String name, bool value);

  /// Wraps `OgaGeneratorParamsSetGuidance`.
  void generatorParamsSetGuidance(
      GenAiPtr handle, String type, String data, bool enableFfTokens);

  /// Wraps `OgaGeneratorParamsGetSearchNumber`.
  double generatorParamsGetSearchNumber(GenAiPtr handle, String name);

  /// Wraps `OgaGeneratorParamsGetSearchBool`.
  bool generatorParamsGetSearchBool(GenAiPtr handle, String name);

  /// Wraps `OgaCreateRequest`.
  GenAiPtr createRequest(GenAiPtr handle);

  /// Wraps `OgaDestroyGenerator`.
  void destroyGenerator(GenAiPtr handle);

  /// Wraps `OgaGenerator_IsDone`.
  bool generatorIsDone(GenAiPtr handle);

  /// Wraps `OgaGenerator_IsSessionTerminated`.
  bool generatorIsSessionTerminated(GenAiPtr handle);

  /// Wraps `OgaGenerator_SetModelInput`.
  void generatorSetModelInput(GenAiPtr handle, String name, GenAiPtr tensor);

  /// Wraps `OgaGenerator_SetInputs`.
  void generatorSetInputs(GenAiPtr handle, GenAiPtr namedTensors);

  /// Wraps `OgaGenerator_AppendTokenSequences`.
  void generatorAppendTokenSequences(GenAiPtr handle, GenAiPtr pSequences);

  /// Wraps `OgaGenerator_AppendTokens`.
  void generatorAppendTokens(GenAiPtr handle, List<int> inputIds);

  /// Wraps `OgaGenerator_TokenCount`.
  int generatorTokenCount(GenAiPtr handle);

  /// Wraps `OgaGenerator_GenerateNextToken`.
  void generatorGenerateNextToken(GenAiPtr handle);

  /// Wraps `OgaGenerator_SetRuntimeOption`.
  void generatorSetRuntimeOption(GenAiPtr handle, String key, String value);

  /// Wraps `OgaGenerator_RewindTo`.
  void generatorRewindTo(GenAiPtr handle, int newLength);

  /// Wraps `OgaGenerator_GetInput`.
  GenAiPtr generatorGetInput(GenAiPtr handle, String name);

  /// Wraps `OgaGenerator_GetOutput`.
  GenAiPtr generatorGetOutput(GenAiPtr handle, String name);

  /// Wraps `OgaGenerator_GetLogits`.
  GenAiPtr generatorGetLogits(GenAiPtr handle);

  /// Wraps `OgaGenerator_SetLogits`.
  void generatorSetLogits(GenAiPtr handle, GenAiPtr tensor);

  /// Wraps `OgaGenerator_GetSequenceCount`.
  int generatorGetSequenceCount(GenAiPtr handle, int index);

  /// Wraps `OgaGenerator_GetSequenceData`.
  List<int> generatorGetSequenceData(GenAiPtr handle, int index);

  /// Wraps `OgaSetActiveAdapter`.
  void setActiveAdapter(GenAiPtr handle, GenAiPtr adapters, String adapterName);

  /// Wraps `OgaDestroyTokenizer`.
  void destroyTokenizer(GenAiPtr handle);

  /// Wraps `OgaTokenizerGetBosTokenId`.
  int tokenizerGetBosTokenId(GenAiPtr handle);

  /// Wraps `OgaTokenizerGetPadTokenId`.
  int tokenizerGetPadTokenId(GenAiPtr handle);

  /// Wraps `OgaTokenizerGetBotTokenId`.
  int tokenizerGetBotTokenId(GenAiPtr handle);

  /// Wraps `OgaTokenizerGetEotTokenId`.
  int tokenizerGetEotTokenId(GenAiPtr handle);

  /// Wraps `OgaTokenizerGetBorTokenId`.
  int tokenizerGetBorTokenId(GenAiPtr handle);

  /// Wraps `OgaTokenizerGetEorTokenId`.
  int tokenizerGetEorTokenId(GenAiPtr handle);

  /// Wraps `OgaTokenizerEncode`.
  void tokenizerEncode(GenAiPtr handle, String str, GenAiPtr sequences);

  /// Wraps `OgaTokenizerEncodeBatch`.
  GenAiPtr tokenizerEncodeBatch(GenAiPtr handle, List<String> strings);

  /// Wraps `OgaTokenizerDecodeBatch`.
  GenAiPtr tokenizerDecodeBatch(GenAiPtr handle, GenAiPtr tensor);

  /// Wraps `OgaTokenizerToTokenId`.
  int tokenizerToTokenId(GenAiPtr handle, String str);

  /// Wraps `OgaTokenizerDecode`.
  String tokenizerDecode(GenAiPtr handle, List<int> tokens);

  /// Wraps `OgaTokenizerApplyChatTemplate`.
  String tokenizerApplyChatTemplate(GenAiPtr handle, String templateStr,
      String messages, String tools, bool addGenerationPrompt);

  /// Wraps `OgaCreateTokenizerStream`.
  GenAiPtr createTokenizerStream(GenAiPtr handle);

  /// Wraps `OgaDestroyMultiModalProcessor`.
  void destroyMultiModalProcessor(GenAiPtr handle);

  /// Wraps `OgaProcessorProcessImages`.
  GenAiPtr processorProcessImages(
      GenAiPtr handle, String prompt, GenAiPtr images);

  /// Wraps `OgaProcessorProcessImagesAndPrompts`.
  GenAiPtr processorProcessImagesAndPrompts(
      GenAiPtr handle, GenAiPtr prompts, GenAiPtr images);

  /// Wraps `OgaProcessorProcessAudios`.
  GenAiPtr processorProcessAudios(
      GenAiPtr handle, String prompt, GenAiPtr audios);

  /// Wraps `OgaProcessorProcessAudiosAndPrompts`.
  GenAiPtr processorProcessAudiosAndPrompts(
      GenAiPtr handle, GenAiPtr prompts, GenAiPtr audios);

  /// Wraps `OgaProcessorProcessImagesAndAudios`.
  GenAiPtr processorProcessImagesAndAudios(
      GenAiPtr handle, String prompt, GenAiPtr images, GenAiPtr audios);

  /// Wraps `OgaProcessorProcessImagesAndAudiosAndPrompts`.
  GenAiPtr processorProcessImagesAndAudiosAndPrompts(
      GenAiPtr handle, GenAiPtr prompts, GenAiPtr images, GenAiPtr audios);

  /// Wraps `OgaProcessorDecode`.
  String processorDecode(GenAiPtr handle, List<int> tokens);

  /// Wraps `OgaCreateTokenizerStreamFromProcessor`.
  GenAiPtr createTokenizerStreamFromProcessor(GenAiPtr handle);

  /// Wraps `OgaDestroyTokenizerStream`.
  void destroyTokenizerStream(GenAiPtr handle);

  /// Wraps `OgaTokenizerStreamDecode`.
  String tokenizerStreamDecode(GenAiPtr handle, int token);

  /// Wraps `OgaDestroyTensor`.
  void destroyTensor(GenAiPtr handle);

  /// Wraps `OgaTensorGetShapeRank`.
  int tensorGetShapeRank(GenAiPtr handle);

  /// Wraps `OgaTensorGetShape`.
  void tensorGetShape(GenAiPtr handle, List<int> shapeDims);

  /// Wraps `OgaDestroyAdapters`.
  void destroyAdapters(GenAiPtr handle);

  /// Wraps `OgaLoadAdapter`.
  void loadAdapter(GenAiPtr handle, String adapterFilePath, String adapterName);

  /// Wraps `OgaUnloadAdapter`.
  void unloadAdapter(GenAiPtr handle, String adapterName);

  /// Wraps `OgaDestroyEngine`.
  void destroyEngine(GenAiPtr handle);

  /// Wraps `OgaEngineStep`.
  GenAiPtr engineStep(GenAiPtr handle);

  /// Wraps `OgaEngineHasPendingRequests`.
  bool engineHasPendingRequests(GenAiPtr handle);

  /// Wraps `OgaEngineAddRequest`.
  void engineAddRequest(GenAiPtr handle, GenAiPtr request);

  /// Wraps `OgaEngineRemoveRequest`.
  void engineRemoveRequest(GenAiPtr handle, GenAiPtr request);

  /// Wraps `OgaDestroyRequest`.
  void destroyRequest(GenAiPtr handle);

  /// Wraps `OgaRequestAddTokens`.
  void requestAddTokens(GenAiPtr handle, GenAiPtr tokens);

  /// Wraps `OgaRequestHasUnseenTokens`.
  bool requestHasUnseenTokens(GenAiPtr handle);

  /// Wraps `OgaRequestGetUnseenToken`.
  int requestGetUnseenToken(GenAiPtr handle);

  /// Wraps `OgaRequestIsDone`.
  bool requestIsDone(GenAiPtr handle);

  /// Wraps `OgaDestroyStreamingProcessor`.
  void destroyStreamingProcessor(GenAiPtr handle);

  /// Wraps `OgaStreamingProcessorProcess`.
  GenAiPtr streamingProcessorProcess(GenAiPtr handle, List<double> audioData);

  /// Wraps `OgaStreamingProcessorFlush`.
  GenAiPtr streamingProcessorFlush(GenAiPtr handle);

  /// Wraps `OgaStreamingProcessorSetOption`.
  void streamingProcessorSetOption(GenAiPtr handle, String key, String value);

  /// Wraps `OgaStreamingProcessorGetOption`.
  String streamingProcessorGetOption(GenAiPtr handle, String key);
}

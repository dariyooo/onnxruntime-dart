// AUTO GENERATED FILE, DO NOT EDIT.
//
// Generated from third_party/onnxruntime-genai/src/ort_genai_c.h.
// Regenerate with `dart run tool/generate_bindings.dart` from this package.

/// The backend for a platform GenAI has no build for.
///
/// Upstream publishes no WebAssembly library, so every call refuses rather
/// than pretending. The point is that the package still compiles into a web
/// application: an application that uses GenAI on native and something else on
/// the web should not fail to build because of an import.
///
/// It names nothing native, which is what lets it be the web half of the
/// conditional export in calls.dart.
library;

import 'dart:typed_data';

import 'interface.dart';
import 'types.dart';

/// The backend for this platform.
GenAiCalls createCalls() => const UnsupportedGenAiCalls();

/// GenAI where there is no GenAI.
final class UnsupportedGenAiCalls implements GenAiCalls {
  const UnsupportedGenAiCalls();

  @override
  void shutdown() =>
      throw const GenAiUnsupported('shutdown');

  @override
  void setTelemetryEnabled(bool enabled) =>
      throw const GenAiUnsupported('setTelemetryEnabled');

  @override
  void setLogBool(String name, bool value) =>
      throw const GenAiUnsupported('setLogBool');

  @override
  void setLogString(String name, String value) =>
      throw const GenAiUnsupported('setLogString');

  @override
  void destroyString(String value) =>
      throw const GenAiUnsupported('destroyString');

  @override
  void setCurrentGpuDeviceId(int deviceId) =>
      throw const GenAiUnsupported('setCurrentGpuDeviceId');

  @override
  int getCurrentGpuDeviceId() =>
      throw const GenAiUnsupported('getCurrentGpuDeviceId');

  @override
  void registerExecutionProviderLibrary(String registrationName, String libraryPath) =>
      throw const GenAiUnsupported('registerExecutionProviderLibrary');

  @override
  void unregisterExecutionProviderLibrary(String registrationName) =>
      throw const GenAiUnsupported('unregisterExecutionProviderLibrary');

  @override
  void destroyNamedTensors(GenAiPtr handle) =>
      throw const GenAiUnsupported('destroyNamedTensors');

  @override
  GenAiPtr createNamedTensors() =>
      throw const GenAiUnsupported('createNamedTensors');

  @override
  GenAiPtr namedTensorsGet(GenAiPtr handle, String name) =>
      throw const GenAiUnsupported('namedTensorsGet');

  @override
  void namedTensorsSet(GenAiPtr handle, String name, GenAiPtr tensor) =>
      throw const GenAiUnsupported('namedTensorsSet');

  @override
  void namedTensorsDelete(GenAiPtr handle, String name) =>
      throw const GenAiUnsupported('namedTensorsDelete');

  @override
  int namedTensorsCount(GenAiPtr handle) =>
      throw const GenAiUnsupported('namedTensorsCount');

  @override
  GenAiPtr namedTensorsGetNames(GenAiPtr handle) =>
      throw const GenAiUnsupported('namedTensorsGetNames');

  @override
  void destroySequences(GenAiPtr handle) =>
      throw const GenAiUnsupported('destroySequences');

  @override
  GenAiPtr createSequences() =>
      throw const GenAiUnsupported('createSequences');

  @override
  int sequencesCount(GenAiPtr handle) =>
      throw const GenAiUnsupported('sequencesCount');

  @override
  void appendTokenSequence(GenAiPtr handle, List<int> tokenPtr) =>
      throw const GenAiUnsupported('appendTokenSequence');

  @override
  void appendTokenToSequence(GenAiPtr handle, int token, int sequenceIndex) =>
      throw const GenAiUnsupported('appendTokenToSequence');

  @override
  int sequencesGetSequenceCount(GenAiPtr handle, int sequenceIndex) =>
      throw const GenAiUnsupported('sequencesGetSequenceCount');

  @override
  List<int> sequencesGetSequenceData(GenAiPtr handle, int sequenceIndex) =>
      throw const GenAiUnsupported('sequencesGetSequenceData');

  @override
  void destroyImages(GenAiPtr handle) =>
      throw const GenAiUnsupported('destroyImages');

  @override
  GenAiPtr loadImage(String imagePath) =>
      throw const GenAiUnsupported('loadImage');

  @override
  GenAiPtr loadImagesFromBuffers(List<Uint8List> imageData) =>
      throw const GenAiUnsupported('loadImagesFromBuffers');

  @override
  void destroyStringArray(GenAiPtr handle) =>
      throw const GenAiUnsupported('destroyStringArray');

  @override
  GenAiPtr loadImages(GenAiPtr handle) =>
      throw const GenAiUnsupported('loadImages');

  @override
  GenAiPtr loadAudios(GenAiPtr handle) =>
      throw const GenAiUnsupported('loadAudios');

  @override
  GenAiPtr createStringArray() =>
      throw const GenAiUnsupported('createStringArray');

  @override
  GenAiPtr createStringArrayFromStrings(List<String> strs) =>
      throw const GenAiUnsupported('createStringArrayFromStrings');

  @override
  void stringArrayAddString(GenAiPtr handle, String str) =>
      throw const GenAiUnsupported('stringArrayAddString');

  @override
  int stringArrayGetCount(GenAiPtr handle) =>
      throw const GenAiUnsupported('stringArrayGetCount');

  @override
  String stringArrayGetString(GenAiPtr handle, int index) =>
      throw const GenAiUnsupported('stringArrayGetString');

  @override
  void destroyAudios(GenAiPtr handle) =>
      throw const GenAiUnsupported('destroyAudios');

  @override
  GenAiPtr loadAudio(String audioPath) =>
      throw const GenAiUnsupported('loadAudio');

  @override
  GenAiPtr loadAudiosFromBuffers(List<Uint8List> audioData) =>
      throw const GenAiUnsupported('loadAudiosFromBuffers');

  @override
  void destroyRuntimeSettings(GenAiPtr handle) =>
      throw const GenAiUnsupported('destroyRuntimeSettings');

  @override
  GenAiPtr createRuntimeSettings() =>
      throw const GenAiUnsupported('createRuntimeSettings');

  @override
  GenAiPtr createModelWithRuntimeSettings(GenAiPtr handle, String configPath) =>
      throw const GenAiUnsupported('createModelWithRuntimeSettings');

  @override
  void destroyConfig(GenAiPtr handle) =>
      throw const GenAiUnsupported('destroyConfig');

  @override
  GenAiPtr createConfig(String configPath) =>
      throw const GenAiUnsupported('createConfig');

  @override
  GenAiPtr createConfigFromPackageEp(String configPath, String ep) =>
      throw const GenAiUnsupported('createConfigFromPackageEp');

  @override
  void configClearProviders(GenAiPtr handle) =>
      throw const GenAiUnsupported('configClearProviders');

  @override
  void configAppendProvider(GenAiPtr handle, String provider) =>
      throw const GenAiUnsupported('configAppendProvider');

  @override
  void configSetProviderOption(GenAiPtr handle, String provider, String key, String value) =>
      throw const GenAiUnsupported('configSetProviderOption');

  @override
  void configAddModelData(GenAiPtr handle, String modelFilename, Uint8List modelData) =>
      throw const GenAiUnsupported('configAddModelData');

  @override
  void configRemoveModelData(GenAiPtr handle, String modelFilename) =>
      throw const GenAiUnsupported('configRemoveModelData');

  @override
  void configSetDecoderProviderOptionsHardwareDeviceType(GenAiPtr handle, String provider, String hardwareDeviceType) =>
      throw const GenAiUnsupported('configSetDecoderProviderOptionsHardwareDeviceType');

  @override
  void configSetDecoderProviderOptionsHardwareDeviceId(GenAiPtr handle, String provider, int hardwareDeviceId) =>
      throw const GenAiUnsupported('configSetDecoderProviderOptionsHardwareDeviceId');

  @override
  void configSetDecoderProviderOptionsHardwareVendorId(GenAiPtr handle, String provider, int hardwareVendorId) =>
      throw const GenAiUnsupported('configSetDecoderProviderOptionsHardwareVendorId');

  @override
  void configClearDecoderProviderOptionsHardwareDeviceType(GenAiPtr handle, String provider) =>
      throw const GenAiUnsupported('configClearDecoderProviderOptionsHardwareDeviceType');

  @override
  void configClearDecoderProviderOptionsHardwareDeviceId(GenAiPtr handle, String provider) =>
      throw const GenAiUnsupported('configClearDecoderProviderOptionsHardwareDeviceId');

  @override
  void configClearDecoderProviderOptionsHardwareVendorId(GenAiPtr handle, String provider) =>
      throw const GenAiUnsupported('configClearDecoderProviderOptionsHardwareVendorId');

  @override
  void configOverlay(GenAiPtr handle, String json) =>
      throw const GenAiUnsupported('configOverlay');

  @override
  GenAiPtr createModelFromConfig(GenAiPtr handle) =>
      throw const GenAiUnsupported('createModelFromConfig');

  @override
  void destroyModel(GenAiPtr handle) =>
      throw const GenAiUnsupported('destroyModel');

  @override
  GenAiPtr createModel(String configPath) =>
      throw const GenAiUnsupported('createModel');

  @override
  String modelGetType(GenAiPtr handle) =>
      throw const GenAiUnsupported('modelGetType');

  @override
  String modelGetDeviceType(GenAiPtr handle) =>
      throw const GenAiUnsupported('modelGetDeviceType');

  @override
  GenAiPtr createGeneratorParams(GenAiPtr handle) =>
      throw const GenAiUnsupported('createGeneratorParams');

  @override
  GenAiPtr createGenerator(GenAiPtr handle, GenAiPtr params) =>
      throw const GenAiUnsupported('createGenerator');

  @override
  GenAiPtr createTokenizer(GenAiPtr handle) =>
      throw const GenAiUnsupported('createTokenizer');

  @override
  GenAiPtr createMultiModalProcessor(GenAiPtr handle) =>
      throw const GenAiUnsupported('createMultiModalProcessor');

  @override
  GenAiPtr createAdapters(GenAiPtr handle) =>
      throw const GenAiUnsupported('createAdapters');

  @override
  GenAiPtr createEngine(GenAiPtr handle) =>
      throw const GenAiUnsupported('createEngine');

  @override
  GenAiPtr createStreamingProcessor(GenAiPtr handle) =>
      throw const GenAiUnsupported('createStreamingProcessor');

  @override
  void destroyGeneratorParams(GenAiPtr handle) =>
      throw const GenAiUnsupported('destroyGeneratorParams');

  @override
  void generatorParamsSetSearchNumber(GenAiPtr handle, String name, double value) =>
      throw const GenAiUnsupported('generatorParamsSetSearchNumber');

  @override
  void generatorParamsSetSearchBool(GenAiPtr handle, String name, bool value) =>
      throw const GenAiUnsupported('generatorParamsSetSearchBool');

  @override
  void generatorParamsSetGuidance(GenAiPtr handle, String type, String data, bool enableFfTokens) =>
      throw const GenAiUnsupported('generatorParamsSetGuidance');

  @override
  double generatorParamsGetSearchNumber(GenAiPtr handle, String name) =>
      throw const GenAiUnsupported('generatorParamsGetSearchNumber');

  @override
  bool generatorParamsGetSearchBool(GenAiPtr handle, String name) =>
      throw const GenAiUnsupported('generatorParamsGetSearchBool');

  @override
  GenAiPtr createRequest(GenAiPtr handle) =>
      throw const GenAiUnsupported('createRequest');

  @override
  void destroyGenerator(GenAiPtr handle) =>
      throw const GenAiUnsupported('destroyGenerator');

  @override
  bool generatorIsDone(GenAiPtr handle) =>
      throw const GenAiUnsupported('generatorIsDone');

  @override
  bool generatorIsSessionTerminated(GenAiPtr handle) =>
      throw const GenAiUnsupported('generatorIsSessionTerminated');

  @override
  void generatorSetModelInput(GenAiPtr handle, String name, GenAiPtr tensor) =>
      throw const GenAiUnsupported('generatorSetModelInput');

  @override
  void generatorSetInputs(GenAiPtr handle, GenAiPtr namedTensors) =>
      throw const GenAiUnsupported('generatorSetInputs');

  @override
  void generatorAppendTokenSequences(GenAiPtr handle, GenAiPtr pSequences) =>
      throw const GenAiUnsupported('generatorAppendTokenSequences');

  @override
  void generatorAppendTokens(GenAiPtr handle, List<int> inputIds) =>
      throw const GenAiUnsupported('generatorAppendTokens');

  @override
  int generatorTokenCount(GenAiPtr handle) =>
      throw const GenAiUnsupported('generatorTokenCount');

  @override
  void generatorGenerateNextToken(GenAiPtr handle) =>
      throw const GenAiUnsupported('generatorGenerateNextToken');

  @override
  List<int> generatorGetNextTokens(GenAiPtr handle) =>
      throw const GenAiUnsupported('generatorGetNextTokens');

  @override
  void generatorSetRuntimeOption(GenAiPtr handle, String key, String value) =>
      throw const GenAiUnsupported('generatorSetRuntimeOption');

  @override
  void generatorRewindTo(GenAiPtr handle, int newLength) =>
      throw const GenAiUnsupported('generatorRewindTo');

  @override
  GenAiPtr generatorGetInput(GenAiPtr handle, String name) =>
      throw const GenAiUnsupported('generatorGetInput');

  @override
  GenAiPtr generatorGetOutput(GenAiPtr handle, String name) =>
      throw const GenAiUnsupported('generatorGetOutput');

  @override
  GenAiPtr generatorGetLogits(GenAiPtr handle) =>
      throw const GenAiUnsupported('generatorGetLogits');

  @override
  void generatorSetLogits(GenAiPtr handle, GenAiPtr tensor) =>
      throw const GenAiUnsupported('generatorSetLogits');

  @override
  int generatorGetSequenceCount(GenAiPtr handle, int index) =>
      throw const GenAiUnsupported('generatorGetSequenceCount');

  @override
  List<int> generatorGetSequenceData(GenAiPtr handle, int index) =>
      throw const GenAiUnsupported('generatorGetSequenceData');

  @override
  void setActiveAdapter(GenAiPtr handle, GenAiPtr adapters, String adapterName) =>
      throw const GenAiUnsupported('setActiveAdapter');

  @override
  void destroyTokenizer(GenAiPtr handle) =>
      throw const GenAiUnsupported('destroyTokenizer');

  @override
  void updateTokenizerOptions(GenAiPtr handle, Map<String, String> options) =>
      throw const GenAiUnsupported('updateTokenizerOptions');

  @override
  int tokenizerGetBosTokenId(GenAiPtr handle) =>
      throw const GenAiUnsupported('tokenizerGetBosTokenId');

  @override
  List<int> tokenizerGetEosTokenIds(GenAiPtr handle) =>
      throw const GenAiUnsupported('tokenizerGetEosTokenIds');

  @override
  int tokenizerGetPadTokenId(GenAiPtr handle) =>
      throw const GenAiUnsupported('tokenizerGetPadTokenId');

  @override
  int tokenizerGetBotTokenId(GenAiPtr handle) =>
      throw const GenAiUnsupported('tokenizerGetBotTokenId');

  @override
  int tokenizerGetEotTokenId(GenAiPtr handle) =>
      throw const GenAiUnsupported('tokenizerGetEotTokenId');

  @override
  int tokenizerGetBorTokenId(GenAiPtr handle) =>
      throw const GenAiUnsupported('tokenizerGetBorTokenId');

  @override
  int tokenizerGetEorTokenId(GenAiPtr handle) =>
      throw const GenAiUnsupported('tokenizerGetEorTokenId');

  @override
  void tokenizerEncode(GenAiPtr handle, String str, GenAiPtr sequences) =>
      throw const GenAiUnsupported('tokenizerEncode');

  @override
  GenAiPtr tokenizerEncodeBatch(GenAiPtr handle, List<String> strings) =>
      throw const GenAiUnsupported('tokenizerEncodeBatch');

  @override
  GenAiPtr tokenizerDecodeBatch(GenAiPtr handle, GenAiPtr tensor) =>
      throw const GenAiUnsupported('tokenizerDecodeBatch');

  @override
  int tokenizerToTokenId(GenAiPtr handle, String str) =>
      throw const GenAiUnsupported('tokenizerToTokenId');

  @override
  String tokenizerDecode(GenAiPtr handle, List<int> tokens) =>
      throw const GenAiUnsupported('tokenizerDecode');

  @override
  String tokenizerApplyChatTemplate(GenAiPtr handle, String templateStr, String messages, String tools, bool addGenerationPrompt) =>
      throw const GenAiUnsupported('tokenizerApplyChatTemplate');

  @override
  GenAiPtr createTokenizerStream(GenAiPtr handle) =>
      throw const GenAiUnsupported('createTokenizerStream');

  @override
  void destroyMultiModalProcessor(GenAiPtr handle) =>
      throw const GenAiUnsupported('destroyMultiModalProcessor');

  @override
  GenAiPtr processorProcessImages(GenAiPtr handle, String prompt, GenAiPtr images) =>
      throw const GenAiUnsupported('processorProcessImages');

  @override
  GenAiPtr processorProcessImagesAndPrompts(GenAiPtr handle, GenAiPtr prompts, GenAiPtr images) =>
      throw const GenAiUnsupported('processorProcessImagesAndPrompts');

  @override
  GenAiPtr processorProcessAudios(GenAiPtr handle, String prompt, GenAiPtr audios) =>
      throw const GenAiUnsupported('processorProcessAudios');

  @override
  GenAiPtr processorProcessAudiosAndPrompts(GenAiPtr handle, GenAiPtr prompts, GenAiPtr audios) =>
      throw const GenAiUnsupported('processorProcessAudiosAndPrompts');

  @override
  GenAiPtr processorProcessImagesAndAudios(GenAiPtr handle, String prompt, GenAiPtr images, GenAiPtr audios) =>
      throw const GenAiUnsupported('processorProcessImagesAndAudios');

  @override
  GenAiPtr processorProcessImagesAndAudiosAndPrompts(GenAiPtr handle, GenAiPtr prompts, GenAiPtr images, GenAiPtr audios) =>
      throw const GenAiUnsupported('processorProcessImagesAndAudiosAndPrompts');

  @override
  String processorDecode(GenAiPtr handle, List<int> tokens) =>
      throw const GenAiUnsupported('processorDecode');

  @override
  GenAiPtr createTokenizerStreamFromProcessor(GenAiPtr handle) =>
      throw const GenAiUnsupported('createTokenizerStreamFromProcessor');

  @override
  void destroyTokenizerStream(GenAiPtr handle) =>
      throw const GenAiUnsupported('destroyTokenizerStream');

  @override
  String tokenizerStreamDecode(GenAiPtr handle, int token) =>
      throw const GenAiUnsupported('tokenizerStreamDecode');

  @override
  void destroyTensor(GenAiPtr handle) =>
      throw const GenAiUnsupported('destroyTensor');

  @override
  int tensorGetType(GenAiPtr handle) =>
      throw const GenAiUnsupported('tensorGetType');

  @override
  int tensorGetShapeRank(GenAiPtr handle) =>
      throw const GenAiUnsupported('tensorGetShapeRank');

  @override
  void tensorGetShape(GenAiPtr handle, List<int> shapeDims) =>
      throw const GenAiUnsupported('tensorGetShape');

  @override
  void destroyAdapters(GenAiPtr handle) =>
      throw const GenAiUnsupported('destroyAdapters');

  @override
  void loadAdapter(GenAiPtr handle, String adapterFilePath, String adapterName) =>
      throw const GenAiUnsupported('loadAdapter');

  @override
  void unloadAdapter(GenAiPtr handle, String adapterName) =>
      throw const GenAiUnsupported('unloadAdapter');

  @override
  void destroyEngine(GenAiPtr handle) =>
      throw const GenAiUnsupported('destroyEngine');

  @override
  GenAiPtr engineStep(GenAiPtr handle) =>
      throw const GenAiUnsupported('engineStep');

  @override
  bool engineHasPendingRequests(GenAiPtr handle) =>
      throw const GenAiUnsupported('engineHasPendingRequests');

  @override
  void engineAddRequest(GenAiPtr handle, GenAiPtr request) =>
      throw const GenAiUnsupported('engineAddRequest');

  @override
  void engineRemoveRequest(GenAiPtr handle, GenAiPtr request) =>
      throw const GenAiUnsupported('engineRemoveRequest');

  @override
  void destroyRequest(GenAiPtr handle) =>
      throw const GenAiUnsupported('destroyRequest');

  @override
  void requestAddTokens(GenAiPtr handle, GenAiPtr tokens) =>
      throw const GenAiUnsupported('requestAddTokens');

  @override
  bool requestHasUnseenTokens(GenAiPtr handle) =>
      throw const GenAiUnsupported('requestHasUnseenTokens');

  @override
  int requestGetUnseenToken(GenAiPtr handle) =>
      throw const GenAiUnsupported('requestGetUnseenToken');

  @override
  bool requestIsDone(GenAiPtr handle) =>
      throw const GenAiUnsupported('requestIsDone');

  @override
  void destroyStreamingProcessor(GenAiPtr handle) =>
      throw const GenAiUnsupported('destroyStreamingProcessor');

  @override
  GenAiPtr streamingProcessorProcess(GenAiPtr handle, List<double> audioData) =>
      throw const GenAiUnsupported('streamingProcessorProcess');

  @override
  GenAiPtr streamingProcessorFlush(GenAiPtr handle) =>
      throw const GenAiUnsupported('streamingProcessorFlush');

  @override
  void streamingProcessorSetOption(GenAiPtr handle, String key, String value) =>
      throw const GenAiUnsupported('streamingProcessorSetOption');

  @override
  String streamingProcessorGetOption(GenAiPtr handle, String key) =>
      throw const GenAiUnsupported('streamingProcessorGetOption');

}

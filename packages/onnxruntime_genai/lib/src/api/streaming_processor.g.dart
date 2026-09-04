// AUTO GENERATED FILE, DO NOT EDIT.
//
// Generated from third_party/onnxruntime-genai/src/ort_genai_c.h.
// Regenerate with `dart run tool/generate_bindings.dart` from this package.

part of 'api.dart';

/// Wraps the `OgaStreamingProcessor` handle.
///
/// Above the backend boundary, so it names no pointer type and forwards
/// everything to whichever backend was selected for this platform.
final class StreamingProcessor extends GenAiHandle {
  StreamingProcessor._(super.handle);

  @override
  void destroy(GenAiPtr handle) => _calls.destroyStreamingProcessor(handle);

  /// Wraps `OgaStreamingProcessorProcess`.
  NamedTensors process(List<double> audioData) =>
      NamedTensors._(_calls.streamingProcessorProcess(handle, audioData));

  /// Wraps `OgaStreamingProcessorFlush`.
  NamedTensors flush() =>
      NamedTensors._(_calls.streamingProcessorFlush(handle));

  /// Wraps `OgaStreamingProcessorSetOption`.
  void setOption(String key, String value) =>
      _calls.streamingProcessorSetOption(handle, key, value);

  /// Wraps `OgaStreamingProcessorGetOption`.
  String getOption(String key) =>
      _calls.streamingProcessorGetOption(handle, key);
}

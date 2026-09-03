// AUTO GENERATED FILE, DO NOT EDIT.
//
// Generated from third_party/onnxruntime-genai/src/ort_genai_c.h.
// Regenerate with `dart run tool/generate_bindings.dart` from this package.

part of 'api.dart';

/// Wraps the `OgaStreamingProcessor` handle.
final class StreamingProcessor extends GenAiHandle<OgaStreamingProcessor> {
  StreamingProcessor._(super.handle);

  @override
  void destroy(Pointer<OgaStreamingProcessor> handle) => OgaDestroyStreamingProcessor(handle);

  /// Wraps `OgaStreamingProcessorProcess`.
  NamedTensors process(List<double> audioData) => withArena((arena) {
        final audioDataNative = arena<Float>(audioData.length);
        for (var i = 0; i < audioData.length; i++) {
          audioDataNative[i] = audioData[i];
        }
        final out = arena<Pointer<OgaNamedTensors>>();
        check(OgaStreamingProcessorProcess(handle, audioDataNative, audioData.length, out));
        return NamedTensors._(out.value);
      });

  /// Wraps `OgaStreamingProcessorFlush`.
  NamedTensors flush() => withArena((arena) {
        final out = arena<Pointer<OgaNamedTensors>>();
        check(OgaStreamingProcessorFlush(handle, out));
        return NamedTensors._(out.value);
      });

  /// Wraps `OgaStreamingProcessorSetOption`.
  void setOption(String key, String value) => withArena((arena) {
        check(OgaStreamingProcessorSetOption(handle, cString(arena, key), cString(arena, value)));
      });

  /// Wraps `OgaStreamingProcessorGetOption`.
  String getOption(String key) => withArena((arena) {
        final out = arena<Pointer<Char>>();
        check(OgaStreamingProcessorGetOption(handle, cString(arena, key), out));
        return takeCString(out.value);
      });

}

// AUTO GENERATED FILE, DO NOT EDIT.
//
// Generated from third_party/onnxruntime-genai/src/ort_genai_c.h.
// Regenerate with `dart run tool/generate_bindings.dart` from this package.

part of 'api.dart';

/// Wraps the `OgaRuntimeSettings` handle.
final class RuntimeSettings extends GenAiHandle<OgaRuntimeSettings> {
  RuntimeSettings._(super.handle);

  @override
  void destroy(Pointer<OgaRuntimeSettings> handle) => OgaDestroyRuntimeSettings(handle);

  /// Wraps `OgaCreateRuntimeSettings`.
  factory RuntimeSettings() => withArena((arena) {
        final out = arena<Pointer<OgaRuntimeSettings>>();
        check(OgaCreateRuntimeSettings(out));
        return RuntimeSettings._(out.value);
      });

  /// Wraps `OgaCreateModelWithRuntimeSettings`.
  Model createModelWithRuntimeSettings(String configPath) => withArena((arena) {
        final out = arena<Pointer<OgaModel>>();
        check(OgaCreateModelWithRuntimeSettings(cString(arena, configPath), handle, out));
        return Model._(out.value);
      });

}

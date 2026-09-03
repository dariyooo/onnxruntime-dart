// AUTO GENERATED FILE, DO NOT EDIT.
//
// Generated from third_party/onnxruntime-genai/src/ort_genai_c.h.
// Regenerate with `dart run tool/generate_bindings.dart` from this package.

part of 'api.dart';

/// Wraps the `OgaAdapters` handle.
final class Adapters extends GenAiHandle<OgaAdapters> {
  Adapters._(super.handle);

  @override
  void destroy(Pointer<OgaAdapters> handle) => OgaDestroyAdapters(handle);

  /// Wraps `OgaLoadAdapter`.
  void loadAdapter(String adapterFilePath, String adapterName) => withArena((arena) {
        check(OgaLoadAdapter(handle, cString(arena, adapterFilePath), cString(arena, adapterName)));
      });

  /// Wraps `OgaUnloadAdapter`.
  void unloadAdapter(String adapterName) => withArena((arena) {
        check(OgaUnloadAdapter(handle, cString(arena, adapterName)));
      });

}

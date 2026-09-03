// AUTO GENERATED FILE, DO NOT EDIT.
//
// Generated from third_party/onnxruntime-genai/src/ort_genai_c.h.
// Regenerate with `dart run tool/generate_bindings.dart` from this package.

part of 'api.dart';

/// Wraps the `OgaNamedTensors` handle.
final class NamedTensors extends GenAiHandle<OgaNamedTensors> {
  NamedTensors._(super.handle);

  @override
  void destroy(Pointer<OgaNamedTensors> handle) => OgaDestroyNamedTensors(handle);

  /// Wraps `OgaCreateNamedTensors`.
  factory NamedTensors() => withArena((arena) {
        final out = arena<Pointer<OgaNamedTensors>>();
        check(OgaCreateNamedTensors(out));
        return NamedTensors._(out.value);
      });

  /// Wraps `OgaNamedTensorsGet`.
  Tensor get(String name) => withArena((arena) {
        final out = arena<Pointer<OgaTensor>>();
        check(OgaNamedTensorsGet(handle, cString(arena, name), out));
        return Tensor._(out.value);
      });

  /// Wraps `OgaNamedTensorsSet`.
  void set(String name, Tensor tensor) => withArena((arena) {
        check(OgaNamedTensorsSet(handle, cString(arena, name), tensor.handle));
      });

  /// Wraps `OgaNamedTensorsDelete`.
  void delete(String name) => withArena((arena) {
        check(OgaNamedTensorsDelete(handle, cString(arena, name)));
      });

  /// Wraps `OgaNamedTensorsCount`.
  int count() => withArena((arena) {
        final out = arena<Size>();
        check(OgaNamedTensorsCount(handle, out));
        return out.value;
      });

  /// Wraps `OgaNamedTensorsGetNames`.
  StringArray getNames() => withArena((arena) {
        final out = arena<Pointer<OgaStringArray>>();
        check(OgaNamedTensorsGetNames(handle, out));
        return StringArray._(out.value);
      });

}

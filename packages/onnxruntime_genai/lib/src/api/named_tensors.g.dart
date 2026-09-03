// AUTO GENERATED FILE, DO NOT EDIT.
//
// Generated from third_party/onnxruntime-genai/src/ort_genai_c.h.
// Regenerate with `dart run tool/generate_bindings.dart` from this package.

part of 'api.dart';

/// Wraps the `OgaNamedTensors` handle.
///
/// Above the backend boundary, so it names no pointer type and forwards
/// everything to whichever backend was selected for this platform.
final class NamedTensors extends GenAiHandle {
  NamedTensors._(super.handle);

  @override
  void destroy(GenAiPtr handle) => _calls.destroyNamedTensors(handle);

  /// Wraps `OgaCreateNamedTensors`.
  factory NamedTensors() => NamedTensors._(_calls.createNamedTensors());

  /// Wraps `OgaNamedTensorsGet`.
  Tensor get(String name) => Tensor._(_calls.namedTensorsGet(handle, name));

  /// Wraps `OgaNamedTensorsSet`.
  void set(String name, GenAiPtr tensor) =>
      _calls.namedTensorsSet(handle, name, tensor);

  /// Wraps `OgaNamedTensorsDelete`.
  void delete(String name) => _calls.namedTensorsDelete(handle, name);

  /// Wraps `OgaNamedTensorsCount`.
  int count() => _calls.namedTensorsCount(handle);

  /// Wraps `OgaNamedTensorsGetNames`.
  StringArray getNames() => StringArray._(_calls.namedTensorsGetNames(handle));
}

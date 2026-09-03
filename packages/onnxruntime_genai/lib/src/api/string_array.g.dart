// AUTO GENERATED FILE, DO NOT EDIT.
//
// Generated from third_party/onnxruntime-genai/src/ort_genai_c.h.
// Regenerate with `dart run tool/generate_bindings.dart` from this package.

part of 'api.dart';

/// Wraps the `OgaStringArray` handle.
///
/// Above the backend boundary, so it names no pointer type and forwards
/// everything to whichever backend was selected for this platform.
final class StringArray extends GenAiHandle {
  StringArray._(super.handle);

  @override
  void destroy(GenAiPtr handle) => _calls.destroyStringArray(handle);

  /// Wraps `OgaLoadImages`.
  Images loadImages() =>
      Images._(_calls.loadImages(handle));

  /// Wraps `OgaLoadAudios`.
  Audios loadAudios() =>
      Audios._(_calls.loadAudios(handle));

  /// Wraps `OgaCreateStringArray`.
  factory StringArray() =>
      StringArray._(_calls.createStringArray());

  /// Wraps `OgaStringArrayAddString`.
  void addString(String str) => _calls.stringArrayAddString(handle, str);

  /// Wraps `OgaStringArrayGetCount`.
  int getCount() => _calls.stringArrayGetCount(handle);

  /// Wraps `OgaStringArrayGetString`.
  String getString(int index) => _calls.stringArrayGetString(handle, index);

}

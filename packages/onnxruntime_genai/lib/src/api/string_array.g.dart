// AUTO GENERATED FILE, DO NOT EDIT.
//
// Generated from third_party/onnxruntime-genai/src/ort_genai_c.h.
// Regenerate with `dart run tool/generate_bindings.dart` from this package.

part of 'api.dart';

/// Wraps the `OgaStringArray` handle.
final class StringArray extends GenAiHandle<OgaStringArray> {
  StringArray._(super.handle);

  @override
  void destroy(Pointer<OgaStringArray> handle) => OgaDestroyStringArray(handle);

  /// Wraps `OgaLoadImages`.
  Images loadImages() => withArena((arena) {
        final out = arena<Pointer<OgaImages>>();
        check(OgaLoadImages(handle, out));
        return Images._(out.value);
      });

  /// Wraps `OgaLoadAudios`.
  Audios loadAudios() => withArena((arena) {
        final out = arena<Pointer<OgaAudios>>();
        check(OgaLoadAudios(handle, out));
        return Audios._(out.value);
      });

  /// Wraps `OgaCreateStringArray`.
  factory StringArray() => withArena((arena) {
        final out = arena<Pointer<OgaStringArray>>();
        check(OgaCreateStringArray(out));
        return StringArray._(out.value);
      });

  /// Wraps `OgaStringArrayAddString`.
  void addString(String str) => withArena((arena) {
        check(OgaStringArrayAddString(handle, cString(arena, str)));
      });

  /// Wraps `OgaStringArrayGetCount`.
  int getCount() => withArena((arena) {
        final out = arena<Size>();
        check(OgaStringArrayGetCount(handle, out));
        return out.value;
      });

  /// Wraps `OgaStringArrayGetString`.
  String getString(int index) => withArena((arena) {
        final out = arena<Pointer<Char>>();
        check(OgaStringArrayGetString(handle, index, out));
        return borrowedCString(out.value);
      });

}

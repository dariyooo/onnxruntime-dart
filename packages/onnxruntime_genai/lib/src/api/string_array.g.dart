// AUTO GENERATED FILE, DO NOT EDIT.
//
// Generated from third_party/onnxruntime-genai/src/ort_genai_c.h.
// Regenerate with `dart run tool/generate_bindings.dart` from this package.

import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../bindings/genai_bindings.g.dart';
import 'support.dart';

/// Wraps the `OgaStringArray` handle.
final class StringArray extends GenAiHandle<OgaStringArray> {
  StringArray._(super.handle);

  @override
  void destroy(Pointer<OgaStringArray> handle) => OgaDestroyStringArray(handle);

  /// Wraps `OgaLoadImages`.
  void loadImages(Images images) => withArena((arena) {
        check(OgaLoadImages(handle, images.handle));
      });

  /// Wraps `OgaLoadAudios`.
  void loadAudios(Audios audios) => withArena((arena) {
        check(OgaLoadAudios(handle, audios.handle));
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
        return takeCString(out.value);
      });

}

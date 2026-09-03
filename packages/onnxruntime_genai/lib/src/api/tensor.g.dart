// AUTO GENERATED FILE, DO NOT EDIT.
//
// Generated from third_party/onnxruntime-genai/src/ort_genai_c.h.
// Regenerate with `dart run tool/generate_bindings.dart` from this package.

import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../bindings/genai_bindings.g.dart';
import 'support.dart';

/// Wraps the `OgaTensor` handle.
final class Tensor extends GenAiHandle<OgaTensor> {
  Tensor._(super.handle);

  @override
  void destroy(Pointer<OgaTensor> handle) => OgaDestroyTensor(handle);

  /// Wraps `OgaTensorGetShapeRank`.
  int getShapeRank() => withArena((arena) {
        final out = arena<Size>();
        check(OgaTensorGetShapeRank(handle, out));
        return out.value;
      });

  /// Wraps `OgaTensorGetShape`.
  void getShape(List<int> shapeDims) => withArena((arena) {
        final shapeDimsNative = arena<Int64>(shapeDims.length);
        for (var i = 0; i < shapeDims.length; i++) {
          shapeDimsNative[i] = shapeDims[i];
        }
        check(OgaTensorGetShape(handle, shapeDimsNative, shapeDims.length));
      });

}

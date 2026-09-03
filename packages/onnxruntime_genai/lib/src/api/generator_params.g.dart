// AUTO GENERATED FILE, DO NOT EDIT.
//
// Generated from third_party/onnxruntime-genai/src/ort_genai_c.h.
// Regenerate with `dart run tool/generate_bindings.dart` from this package.

import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../bindings/genai_bindings.g.dart';
import 'support.dart';

/// Wraps the `OgaGeneratorParams` handle.
final class GeneratorParams extends GenAiHandle<OgaGeneratorParams> {
  GeneratorParams._(super.handle);

  @override
  void destroy(Pointer<OgaGeneratorParams> handle) => OgaDestroyGeneratorParams(handle);

  /// Wraps `OgaGeneratorParamsSetSearchNumber`.
  void setSearchNumber(String name, double value) => withArena((arena) {
        check(OgaGeneratorParamsSetSearchNumber(handle, cString(arena, name), value));
      });

  /// Wraps `OgaGeneratorParamsSetSearchBool`.
  void setSearchBool(String name, bool value) => withArena((arena) {
        check(OgaGeneratorParamsSetSearchBool(handle, cString(arena, name), value));
      });

  /// Wraps `OgaGeneratorParamsSetGuidance`.
  void setGuidance(String type, String data, bool enableFfTokens) => withArena((arena) {
        check(OgaGeneratorParamsSetGuidance(handle, cString(arena, type), cString(arena, data), enableFfTokens));
      });

  /// Wraps `OgaCreateRequest`.
  Request createRequest() => withArena((arena) {
        final out = arena<Pointer<OgaRequest>>();
        check(OgaCreateRequest(handle, out));
        return Request._(out.value);
      });

}

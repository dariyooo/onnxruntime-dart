// AUTO GENERATED FILE, DO NOT EDIT.
//
// Generated from third_party/onnxruntime-genai/src/ort_genai_c.h.
// Regenerate with `dart run tool/generate_bindings.dart` from this package.

import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../bindings/genai_bindings.g.dart';
import 'support.dart';

/// Wraps the `OgaRequest` handle.
final class Request extends GenAiHandle<OgaRequest> {
  Request._(super.handle);

  @override
  void destroy(Pointer<OgaRequest> handle) => OgaDestroyRequest(handle);

  /// Wraps `OgaRequestAddTokens`.
  void addTokens(Sequences tokens) => withArena((arena) {
        check(OgaRequestAddTokens(handle, tokens.handle));
      });

  /// Wraps `OgaRequestHasUnseenTokens`.
  bool hasUnseenTokens() => withArena((arena) {
        final out = arena<Bool>();
        check(OgaRequestHasUnseenTokens(handle, out));
        return out.value;
      });

  /// Wraps `OgaRequestGetUnseenToken`.
  int getUnseenToken() => withArena((arena) {
        final out = arena<Size>();
        check(OgaRequestGetUnseenToken(handle, out));
        return out.value;
      });

  /// Wraps `OgaRequestIsDone`.
  bool isDone() => withArena((arena) {
        final out = arena<Bool>();
        check(OgaRequestIsDone(handle, out));
        return out.value;
      });

}

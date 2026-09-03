// AUTO GENERATED FILE, DO NOT EDIT.
//
// Generated from third_party/onnxruntime-genai/src/ort_genai_c.h.
// Regenerate with `dart run tool/generate_bindings.dart` from this package.

import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../bindings/genai_bindings.g.dart';
import 'support.dart';

/// Wraps the `OgaEngine` handle.
final class Engine extends GenAiHandle<OgaEngine> {
  Engine._(super.handle);

  @override
  void destroy(Pointer<OgaEngine> handle) => OgaDestroyEngine(handle);

  /// Wraps `OgaEngineStep`.
  void step(Request request) => withArena((arena) {
        check(OgaEngineStep(handle, request.handle));
      });

  /// Wraps `OgaEngineHasPendingRequests`.
  bool hasPendingRequests() => withArena((arena) {
        final out = arena<Bool>();
        check(OgaEngineHasPendingRequests(handle, out));
        return out.value;
      });

  /// Wraps `OgaEngineAddRequest`.
  void addRequest(Request request) => withArena((arena) {
        check(OgaEngineAddRequest(handle, request.handle));
      });

  /// Wraps `OgaEngineRemoveRequest`.
  void removeRequest(Request request) => withArena((arena) {
        check(OgaEngineRemoveRequest(handle, request.handle));
      });

}

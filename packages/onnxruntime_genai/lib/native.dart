/// The complete ONNX Runtime GenAI C API, as generated.
///
/// Every function the pinned header exports is reachable here, because the
/// bindings are generated from that header rather than hand-written. That makes
/// completeness a property of the package instead of a goal: anything the C API
/// can do, this library can do on the day the header ships it.
///
/// `onnxruntime_genai.dart` is the ergonomic half. Its wrappers take and return
/// Dart values, allocate what a call needs, release it afterwards, and turn a
/// failed `OgaResult` into a [GenAiException]. Most of the API has one, and the
/// generator lists what it left alone, and why, in `lib/src/api/unmapped.txt`.
///
/// What is left alone is left alone deliberately rather than forgotten. A
/// `void*` buffer whose ownership the header does not state, a raw `const
/// int32_t*` that has to be paired with a separate count call, a callback that
/// needs a native closure with a lifetime someone has to choose: guessing at any
/// of those produces a wrapper that compiles and lies. Reach for this library
/// for those, and the arena and error helpers below are the same ones the
/// generated code uses:
///
/// ```dart
/// import 'package:onnxruntime_genai/native.dart';
///
/// withArena((arena) {
///   final out = arena<Pointer<Char>>();
///   check(OgaSomethingNotWrapped(handle, out));
///   return takeCString(out.value);
/// });
/// ```
library;

export 'src/backend/ffi_support.dart'
    show borrowedCString, check, cString, readCString, takeCString, withArena;
export 'src/backend/types.dart' show GenAiException, GenAiHandle, GenAiPtr;
export 'src/bindings/genai_bindings.g.dart';

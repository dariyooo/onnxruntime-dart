/// Annotations marking where the platforms differ.
library;

import 'package:meta/meta_meta.dart';

/// Marks API that ONNX Runtime's WebAssembly build cannot support.
///
/// Calling it on the web throws [UnsupportedError] carrying [reason]. The
/// annotation exists so the limit shows up in the signature and in generated
/// documentation, rather than only when someone runs into it.
///
/// It is not a reason to leave something out. Web supports a smaller C surface
/// than native does, and shrinking the API to their intersection would make
/// web's limits everyone's limits.
///
/// ```dart
/// @NativeOnly('the WebAssembly build exports no asynchronous run')
/// Future<Map<String, OrtValue>> run(Map<String, OrtValue> inputs);
/// ```
@Target({
  TargetKind.classType,
  TargetKind.constructor,
  TargetKind.function,
  TargetKind.getter,
  TargetKind.method,
  TargetKind.setter,
})
final class NativeOnly {
  const NativeOnly(this.reason);

  /// Why the WebAssembly build cannot do this, in a form worth putting in an
  /// error message.
  final String reason;
}

/// Throws [UnsupportedError] describing what is unavailable here.
///
/// Call from the web implementation of anything marked [NativeOnly] so the
/// runtime message and the annotation say the same thing.
Never unsupportedOnWeb(String member, String reason) => throw UnsupportedError(
      '$member is not available on the web: $reason.',
    );

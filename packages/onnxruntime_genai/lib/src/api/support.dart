/// What the generated wrappers stand on.
///
/// Hand written on purpose, and small on purpose: everything here is a rule
/// that holds for every call, so stating it once is better than emitting it a
/// hundred and fifty times.
library;

import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../bindings/genai_bindings.g.dart';

/// A failure reported by ONNX Runtime GenAI.
///
/// GenAI reports failure by returning a result object rather than by a code,
/// and that object owns its message. [check] takes the message and releases
/// it, so nothing outside this file ever holds one.
final class GenAiException implements Exception {
  GenAiException(this.message);

  final String message;

  @override
  String toString() => 'GenAiException: $message';
}

/// Throws if [result] reports a failure, and releases it either way.
///
/// Null is success, which is the whole convention: every fallible call in the
/// C API returns `OgaResult*` and null means it worked.
void check(Pointer<OgaResult> result) {
  if (result == nullptr) return;
  // Read before destroying. The string belongs to the result and does not
  // outlive it.
  final message = OgaResultGetError(result).cast<Utf8>().toDartString();
  OgaDestroyResult(result);
  throw GenAiException(message);
}

/// A handle that has to be released, and refuses use once it has been.
///
/// The same contract as the base package: release is explicit, because a
/// finalizer does not run in time to matter and cannot be relied on to run at
/// all. Using a released handle is a [StateError] rather than a crash.
abstract base class GenAiHandle<T extends NativeType> {
  GenAiHandle(this._handle);

  Pointer<T>? _handle;

  /// The live handle, or a [StateError] if it has been released.
  Pointer<T> get handle {
    final live = _handle;
    if (live == null) {
      throw StateError(
        '$runtimeType has been released. Values read from it before that stay '
        'valid; the handle itself does not.',
      );
    }
    return live;
  }

  /// Whether this still owns something.
  bool get isReleased => _handle == null;

  /// Releases the native object. Calling twice is an error, not a no-op: a
  /// double release is a bug worth hearing about rather than absorbing.
  void release() {
    final live = handle;
    destroy(live);
    _handle = null;
  }

  /// How this particular handle is freed. Generated per type.
  void destroy(Pointer<T> handle);
}

/// Runs [body] with an arena, freeing everything it allocated afterwards.
///
/// Native calls that take strings or lists need them in native memory for the
/// duration of the call and not one instant longer.
R withArena<R>(R Function(Arena arena) body) => using(body);

/// [text] as a NUL terminated C string in [arena].
Pointer<Char> cString(Arena arena, String text) =>
    text.toNativeUtf8(allocator: arena).cast<Char>();

/// A C string as Dart, or null when it is null.
String? readCString(Pointer<Char> value) =>
    value == nullptr ? null : value.cast<Utf8>().toDartString();

/// A C string GenAI still owns, copied out and left alone.
///
/// The counterpart to [takeCString]. Which one applies is not a guess: the
/// header says so, and freeing a borrowed string aborts the process.
String borrowedCString(Pointer<Char> value) =>
    value.cast<Utf8>().toDartString();

/// A C string GenAI handed over ownership of, copied out and then freed.
String takeCString(Pointer<Char> value) {
  final text = value.cast<Utf8>().toDartString();
  OgaDestroyString(value);
  return text;
}

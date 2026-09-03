/// What the native backend stands on.
///
/// Hand written on purpose, and small on purpose: everything here is a rule
/// that holds for every call, so stating it once is better than emitting it a
/// hundred and fifty times.
library;

import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../bindings/genai_bindings.g.dart';
import 'types.dart';

/// A [GenAiPtr] as the pointer type the C API wants.
///
/// The one place the boundary is crossed in that direction. Above it a handle
/// is an integer and nothing more.
Pointer<T> pointer<T extends NativeType>(GenAiPtr handle) =>
    Pointer<Never>.fromAddress(handle.address).cast<T>();

/// A pointer as the handle the shared code passes around.
GenAiPtr handleOf(Pointer<NativeType> value) => GenAiPtr(value.address);

/// Throws if [result] reports a failure, and releases it either way.
///
/// Null is success, which is the whole convention: every fallible call in the
/// C API returns `OgaResult*` and null means it worked. The message belongs to
/// the result and does not outlive it, so it is read before the release.
void check(Pointer<OgaResult> result) {
  if (result == nullptr) return;
  final message = OgaResultGetError(result).cast<Utf8>().toDartString();
  OgaDestroyResult(result);
  throw GenAiException(message);
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

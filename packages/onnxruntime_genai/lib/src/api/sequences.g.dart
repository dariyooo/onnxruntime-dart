// AUTO GENERATED FILE, DO NOT EDIT.
//
// Generated from third_party/onnxruntime-genai/src/ort_genai_c.h.
// Regenerate with `dart run tool/generate_bindings.dart` from this package.

part of 'api.dart';

/// Wraps the `OgaSequences` handle.
final class Sequences extends GenAiHandle<OgaSequences> {
  Sequences._(super.handle);

  @override
  void destroy(Pointer<OgaSequences> handle) => OgaDestroySequences(handle);

  /// Wraps `OgaCreateSequences`.
  factory Sequences() => withArena((arena) {
        final out = arena<Pointer<OgaSequences>>();
        check(OgaCreateSequences(out));
        return Sequences._(out.value);
      });

  /// Wraps `OgaSequencesCount`.
  int count() =>
      OgaSequencesCount(handle);

  /// Wraps `OgaAppendTokenSequence`.
  void appendTokenSequence(List<int> tokenPtr) => withArena((arena) {
        final tokenPtrNative = arena<Int32>(tokenPtr.length);
        for (var i = 0; i < tokenPtr.length; i++) {
          tokenPtrNative[i] = tokenPtr[i];
        }
        check(OgaAppendTokenSequence(tokenPtrNative, tokenPtr.length, handle));
      });

  /// Wraps `OgaAppendTokenToSequence`.
  void appendTokenToSequence(int token, int sequenceIndex) => withArena((arena) {
        check(OgaAppendTokenToSequence(token, handle, sequenceIndex));
      });

  /// Wraps `OgaSequencesGetSequenceCount`.
  int getSequenceCount(int sequenceIndex) =>
      withArena((arena) => OgaSequencesGetSequenceCount(handle, sequenceIndex));

}

// AUTO GENERATED FILE, DO NOT EDIT.
//
// Generated from third_party/onnxruntime-genai/src/ort_genai_c.h.
// Regenerate with `dart run tool/generate_bindings.dart` from this package.

part of 'api.dart';

/// Wraps the `OgaSequences` handle.
///
/// Above the backend boundary, so it names no pointer type and forwards
/// everything to whichever backend was selected for this platform.
final class Sequences extends GenAiHandle {
  Sequences._(super.handle);

  @override
  void destroy(GenAiPtr handle) => _calls.destroySequences(handle);

  /// Wraps `OgaCreateSequences`.
  factory Sequences() => Sequences._(_calls.createSequences());

  /// Wraps `OgaSequencesCount`.
  int count() => _calls.sequencesCount(handle);

  /// Wraps `OgaAppendTokenSequence`.
  void appendTokenSequence(List<int> tokenPtr) =>
      _calls.appendTokenSequence(handle, tokenPtr);

  /// Wraps `OgaAppendTokenToSequence`.
  void appendTokenToSequence(int token, int sequenceIndex) =>
      _calls.appendTokenToSequence(handle, token, sequenceIndex);

  /// Wraps `OgaSequencesGetSequenceCount`.
  int getSequenceCount(int sequenceIndex) =>
      _calls.sequencesGetSequenceCount(handle, sequenceIndex);

  /// Wraps `OgaSequencesGetSequenceData`.
  List<int> getSequenceData(int sequenceIndex) =>
      _calls.sequencesGetSequenceData(handle, sequenceIndex);
}

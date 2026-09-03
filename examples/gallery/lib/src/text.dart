/// Turning a sentence into the integers a transformer expects.
///
/// WordPiece, which is what BERT and every model derived from it uses,
/// including MiniLM. The vocabulary is the model's own `vocab.txt`, downloaded
/// beside it, because a tokenizer that disagrees with the model produces
/// embeddings that are wrong in a way nothing downstream can notice.
///
/// Uncased and ASCII-punctuation only, which matches what MiniLM was trained
/// with. It is not a general implementation and does not pretend to be: a
/// sentence outside that alphabet ends up as unknown tokens, which is visible
/// in the output rather than silent.
library;

import 'dart:math' as math;

/// A WordPiece vocabulary and the tokenizer that goes with it.
class WordPiece {
  WordPiece(this.vocabulary)
      : unknown = vocabulary['[UNK]'] ?? 100,
        classification = vocabulary['[CLS]'] ?? 101,
        separator = vocabulary['[SEP]'] ?? 102;

  /// Reads the one-token-per-line form `vocab.txt` is written in, where the
  /// line number is the id.
  factory WordPiece.parse(String text) {
    final vocabulary = <String, int>{};
    final lines = text.split('\n');
    for (var i = 0; i < lines.length; i++) {
      final token = lines[i].trim();
      if (token.isNotEmpty) vocabulary[token] = i;
    }
    return WordPiece(vocabulary);
  }

  final Map<String, int> vocabulary;
  final int unknown;
  final int classification;
  final int separator;

  /// The ids for [text], with the [CLS] and [SEP] markers the model expects.
  List<int> encode(String text, {int maximum = 128}) {
    final ids = <int>[classification];
    for (final word in _split(text.toLowerCase())) {
      ids.addAll(_pieces(word));
      if (ids.length >= maximum - 1) break;
    }
    if (ids.length > maximum - 1) ids.removeRange(maximum - 1, ids.length);
    ids.add(separator);
    return ids;
  }

  /// Words and punctuation, each on its own, which is what WordPiece expects
  /// to be handed.
  static List<String> _split(String text) {
    final out = <String>[];
    final buffer = StringBuffer();
    for (final rune in text.runes) {
      final character = String.fromCharCode(rune);
      final isLetterOrDigit = RegExp(r'[a-z0-9]').hasMatch(character);
      if (isLetterOrDigit) {
        buffer.write(character);
        continue;
      }
      if (buffer.isNotEmpty) {
        out.add(buffer.toString());
        buffer.clear();
      }
      if (character.trim().isNotEmpty) out.add(character);
    }
    if (buffer.isNotEmpty) out.add(buffer.toString());
    return out;
  }

  /// Greedy longest-match-first, which is the algorithm WordPiece is.
  ///
  /// A word that cannot be covered at all becomes one unknown token rather
  /// than a run of them, because that is what the training did.
  List<int> _pieces(String word) {
    if (vocabulary.containsKey(word)) return [vocabulary[word]!];

    final pieces = <int>[];
    var start = 0;
    while (start < word.length) {
      var end = word.length;
      int? found;
      while (start < end) {
        final piece = start == 0
            ? word.substring(start, end)
            : '##${word.substring(start, end)}';
        final id = vocabulary[piece];
        if (id != null) {
          found = id;
          break;
        }
        end--;
      }
      if (found == null) return [unknown];
      pieces.add(found);
      start = end;
    }
    return pieces;
  }
}

/// How alike two vectors point, which is how sentence embeddings are compared.
double cosineSimilarity(List<double> a, List<double> b) {
  if (a.length != b.length || a.isEmpty) return 0;
  var dot = 0.0;
  var lengthA = 0.0;
  var lengthB = 0.0;
  for (var i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    lengthA += a[i] * a[i];
    lengthB += b[i] * b[i];
  }
  if (lengthA == 0 || lengthB == 0) return 0;
  return dot / (math.sqrt(lengthA) * math.sqrt(lengthB));
}

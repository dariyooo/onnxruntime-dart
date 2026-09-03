/// Running a model, and saying what happened.
///
/// One entry point per kind of model, because the interesting differences are
/// in what goes in and what comes out rather than in the run itself. Every one
/// of them creates the session with profiling on and reads the profile
/// afterwards, so the answer to "which provider ran" comes from the runtime
/// rather than from what was asked for.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:onnxruntime_dart/onnxruntime_dart.dart';
import 'package:path/path.dart' as p;

import 'catalogue.dart';
import 'diagnostics.dart';
import 'images.dart';
import 'text.dart';

/// What a run produced, ready to show.
class Outcome {
  const Outcome({
    required this.report,
    required this.lines,
    this.detail,
  });

  final RunReport report;

  /// The result, a line at a time.
  final List<String> lines;

  /// Anything that needs more room than a line.
  final String? detail;
}

/// Which provider to ask for.
class ProviderChoice {
  const ProviderChoice(this.name, this.label);

  /// Null means ask for nothing and take the CPU, which every build has.
  final String? name;
  final String label;

  static const cpu = ProviderChoice(null, 'CPU');
  static const webgpu = ProviderChoice('webgpu', 'WebGPU');
}

/// Opens a session on [file], with profiling on so the run can be accounted
/// for afterwards.
///
/// The profile is written next to the model rather than into the working
/// directory, which on a phone is not somewhere writable.
Future<(Session, List<String>)> _open(
  File file,
  ProviderChoice provider,
  Directory scratch,
) async {
  final requested = provider.name == null ? <String>[] : [provider.name!];
  final options = SessionOptions(
    providers: [
      for (final name in requested)
        (name: name, configuration: <String, String>{}),
    ],
    profileFilePrefix: p.join(scratch.path, 'profile'),
  );
  final session =
      await Session.load(await file.readAsBytes(), options: options);
  return (session, requested);
}

/// Runs [feeds], and says how long it took.
///
/// Deliberately not where the profile is read. `EndProfiling` closes the trace
/// for the whole session and can only be answered once, so a caller that runs
/// twice on one session has to ask for the report after the last run rather
/// than after each. The transformer does exactly that.
Future<(Map<String, OrtTensor>, Duration)> _run(
  Session session,
  Map<String, OrtTensor> feeds,
) async {
  final clock = Stopwatch()..start();
  final outputs = await session.runAsync(feeds);
  clock.stop();
  return (outputs, clock.elapsed);
}

/// Closes the profile and reads it, which can only happen once per session.
Future<RunReport> _report(
  Session session,
  Duration wallTime,
  List<String> requested,
) async {
  final profile = session.endProfiling();
  if (profile == null) {
    return RunReport(
      wallTime: wallTime,
      requested: requested,
      nodesByProvider: const {},
      warnings: const ['profiling produced no file'],
    );
  }

  final report = readProfile(profile, wallTime: wallTime, requested: requested);

  // Deleted once read. The runtime names each profile after the moment it was
  // written, so they do not overwrite each other, and a directory of models
  // quietly fills with them otherwise.
  final file = File(profile);
  if (file.existsSync()) await file.delete();
  return report;
}

/// A classifier: a picture in, the likeliest classes out.
Future<Outcome> runClassifier({
  required ModelSpec spec,
  required Directory directory,
  required Uint8List image,
  required ProviderChoice provider,
}) async {
  final picture = await Picture.decode(image);
  final labels = await File(p.join(directory.path, 'synset.txt')).readAsLines();

  final (session, requested) = await _open(
      File(p.join(directory.path, spec.model.name)), provider, directory);
  try {
    final input = session.inputs.single;
    final tensor = OrtTensor.fromData(
      OrtElementType.float32,
      asImagenetInput(picture, 224),
      [1, 3, 224, 224],
    );
    try {
      final (outputs, took) = await _run(session, {input.name: tensor});
      final report = await _report(session, took, requested);
      try {
        final view = outputs.values.first.view;
        final scores = view.float32s.toList();
        final probabilities = asProbabilities(scores);

        final ranked = List.generate(probabilities.length, (i) => i)
          ..sort((a, b) => probabilities[b].compareTo(probabilities[a]));

        return Outcome(
          report: report,
          lines: [
            for (final index in ranked.take(5))
              '${(probabilities[index] * 100).toStringAsFixed(1)}%  '
                  '${_label(labels, index)}',
          ],
          detail: 'Output shape ${view.shape}, '
              '${picture.width}x${picture.height} resized to 224x224.',
        );
      } finally {
        for (final output in outputs.values) {
          output.release();
        }
      }
    } finally {
      tensor.release();
    }
  } finally {
    session.release();
  }
}

/// A detector: a picture in, boxes out.
///
/// The boxes are reported as counts and shapes rather than drawn. Decoding
/// YOLO's three output tensors into rectangles is the model's business rather
/// than the runtime's, and what this app is here to show is that all three
/// arrive with the right shapes and dtypes.
Future<Outcome> runDetector({
  required ModelSpec spec,
  required Directory directory,
  required Uint8List image,
  required ProviderChoice provider,
}) async {
  final picture = await Picture.decode(image);
  final (session, requested) = await _open(
      File(p.join(directory.path, spec.model.name)), provider, directory);
  try {
    // Two inputs: the picture, and the size it came from. The second is why
    // the boxes come back in the original coordinates.
    final data = OrtTensor.fromData(
      OrtElementType.float32,
      asUnitInput(picture, 416),
      [1, 3, 416, 416],
    );
    final shape = OrtTensor.fromData(
      OrtElementType.float32,
      Float32List.fromList(
          [picture.height.toDouble(), picture.width.toDouble()]),
      [1, 2],
    );
    try {
      final names = session.inputs.map((i) => i.name).toList();
      final (outputs, took) =
          await _run(session, {names.first: data, names.last: shape});
      final report = await _report(session, took, requested);
      try {
        return Outcome(
          report: report,
          lines: [
            for (final entry in outputs.entries)
              '${entry.key}: ${entry.value.view.shape} '
                  '${entry.value.view.elementCount} values',
          ],
          detail: 'Three outputs of different ranks and dtypes, which is the '
              'part worth checking. Turning them into rectangles is YOLO\'s '
              'own arithmetic and is left to the reader.',
        );
      } finally {
        for (final output in outputs.values) {
          output.release();
        }
      }
    } finally {
      data.release();
      shape.release();
    }
  } finally {
    session.release();
  }
}

/// A transformer: two sentences in, how alike they are out.
Future<Outcome> runTransformer({
  required ModelSpec spec,
  required Directory directory,
  required String first,
  required String second,
  required ProviderChoice provider,
}) async {
  final tokenizer = WordPiece.parse(
    await File(p.join(directory.path, 'vocab.txt')).readAsString(),
  );
  final (session, requested) = await _open(
      File(p.join(directory.path, spec.model.name)), provider, directory);
  try {
    final embeddings = <List<double>>[];
    // Both sentences go through the same session, so the time is the sum and
    // the profile covers both. Asking for the profile between them would
    // close it and leave the second run unaccounted for.
    var took = Duration.zero;

    for (final sentence in [first, second]) {
      final ids = tokenizer.encode(sentence);
      final length = ids.length;

      // Three inputs of the same shape: the tokens, which of them are real,
      // and which sentence each belongs to. One sentence, so the last is zero
      // throughout.
      final feeds = {
        'input_ids': OrtTensor.fromData(
          OrtElementType.int64,
          Int64List.fromList(ids),
          [1, length],
        ),
        'attention_mask': OrtTensor.fromData(
          OrtElementType.int64,
          Int64List.fromList(List.filled(length, 1)),
          [1, length],
        ),
        'token_type_ids': OrtTensor.fromData(
          OrtElementType.int64,
          Int64List(length),
          [1, length],
        ),
      };
      try {
        final (outputs, elapsed) = await _run(session, feeds);
        took += elapsed;
        try {
          // Mean pooling over the tokens, which is what this model's own card
          // says to do with its last hidden state.
          final view = outputs.values.first.view;
          final hidden = view.shape.last;
          final values = view.float32s;
          final pooled = List<double>.filled(hidden, 0);
          for (var token = 0; token < length; token++) {
            for (var i = 0; i < hidden; i++) {
              pooled[i] += values[token * hidden + i];
            }
          }
          for (var i = 0; i < hidden; i++) {
            pooled[i] /= length;
          }
          embeddings.add(pooled);
        } finally {
          for (final output in outputs.values) {
            output.release();
          }
        }
      } finally {
        for (final tensor in feeds.values) {
          tensor.release();
        }
      }
    }

    final report = await _report(session, took, requested);
    final similarity = cosineSimilarity(embeddings.first, embeddings.last);
    return Outcome(
      report: report,
      lines: [
        'similarity ${similarity.toStringAsFixed(3)}',
        '${embeddings.first.length} dimensions per sentence',
      ],
      detail: 'Two runs on one session, one sentence each, and the timing '
          'and profile above cover both. 1.0 would be the same direction, '
          '0.0 unrelated.',
    );
  } finally {
    session.release();
  }
}

/// A recurrent model: a question and a passage in, the answer span out.
Future<Outcome> runRecurrent({
  required ModelSpec spec,
  required Directory directory,
  required String passage,
  required String question,
  required ProviderChoice provider,
}) async {
  final (session, requested) = await _open(
      File(p.join(directory.path, spec.model.name)), provider, directory);
  try {
    // BiDAF takes each word twice: once whole, and once split into its first
    // sixteen characters. Both are string tensors, which almost nothing else
    // in this app uses.
    final context = _words(passage);
    final query = _words(question);

    final feeds = {
      'context_word': OrtTensor.fromStrings(context, [context.length, 1]),
      'context_char': OrtTensor.fromStrings(
        _characters(context),
        [context.length, 1, 1, 16],
      ),
      'query_word': OrtTensor.fromStrings(query, [query.length, 1]),
      'query_char': OrtTensor.fromStrings(
        _characters(query),
        [query.length, 1, 1, 16],
      ),
    };
    try {
      final (outputs, took) = await _run(session, feeds);
      final report = await _report(session, took, requested);
      try {
        // Two outputs, the first and last word of the answer.
        final start = outputs['start_pos']?.view.int32s.first ?? 0;
        final end = outputs['end_pos']?.view.int32s.first ?? 0;
        final answer = start <= end && end < context.length
            ? context.sublist(start, end + 1).join(' ')
            : '(the model pointed outside the passage)';

        return Outcome(
          report: report,
          lines: ['"$answer"', 'words $start to $end of ${context.length}'],
          detail: 'String tensors in and out, and LSTMs in between.',
        );
      } finally {
        for (final output in outputs.values) {
          output.release();
        }
      }
    } finally {
      for (final tensor in feeds.values) {
        tensor.release();
      }
    }
  } finally {
    session.release();
  }
}

/// Lower-cased words, which is what BiDAF was trained on.
List<String> _words(String text) => text
    .toLowerCase()
    .split(RegExp(r'[^a-z0-9]+'))
    .where((word) => word.isNotEmpty)
    .toList();

/// Each word as sixteen characters, padded, which is the shape BiDAF wants.
List<String> _characters(List<String> words) => [
      for (final word in words)
        for (var i = 0; i < 16; i++) i < word.length ? word[i] : '',
    ];

String _label(List<String> labels, int index) {
  if (index >= labels.length) return 'class $index';
  final line = labels[index];
  // synset.txt is "n01440764 tench, Tinca tinca": the id, then the names.
  final space = line.indexOf(' ');
  return space < 0 ? line : line.substring(space + 1);
}

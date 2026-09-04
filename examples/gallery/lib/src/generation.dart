/// Running the generative model, which goes through the GenAI package.
///
/// Different from everything else here on purpose. GenAI owns the tokenizer,
/// the sampling and the loop, so this does not build tensors or read outputs:
/// it hands over a prompt and takes back tokens one at a time. That is the
/// whole point of the package existing, and the reason it is a separate
/// binding rather than a helper over the runtime.
///
/// There is no profile to read here. GenAI creates its own ONNX Runtime
/// sessions inside the model directory's configuration, so which provider ran
/// is what the model reports rather than something this side can account for
/// node by node.
library;

import 'dart:async';

import 'package:onnxruntime_genai/onnxruntime_genai.dart';

/// One token as it arrives, so the caller can show text while it is written.
class Token {
  const Token(this.text, this.index);
  final String text;
  final int index;
}

/// What the model says it is running on.
class Generation {
  const Generation({required this.deviceType, required this.modelType});
  final String deviceType;
  final String modelType;
}

/// Streams a completion for [prompt] out of the model in [directory].
///
/// The handles are released in the order they depend on each other, and on
/// every path: a generator outlives nothing, and the model outlives all of it.
Stream<Token> generate({
  required String directory,
  required String prompt,
  required int maximumTokens,
  void Function(Generation)? onReady,
}) async* {
  final model = Model(directory);
  try {
    onReady?.call(Generation(
      deviceType: model.getDeviceType(),
      modelType: model.getType(),
    ));

    final tokenizer = model.createTokenizer();
    try {
      final params = model.createGeneratorParams();
      try {
        params.setSearchNumber('max_length', maximumTokens.toDouble());

        final generator = model.createGenerator(params.handle);
        try {
          final sequences = Sequences();
          try {
            // The instruction format Phi-3 was tuned with. A bare prompt runs
            // and answers worse, which looks like a bad model rather than a
            // missing template.
            tokenizer.encode(
              '<|user|>\n$prompt<|end|>\n<|assistant|>\n',
              sequences.handle,
            );
            generator.appendTokenSequences(sequences.handle);
          } finally {
            sequences.release();
          }

          final stream = tokenizer.createTokenizerStream();
          try {
            var index = 0;
            while (!generator.isDone()) {
              generator.generateNextToken();
              final tokens = generator.getNextTokens();
              if (tokens.isEmpty) continue;
              yield Token(stream.decode(tokens.last), index++);
              // Back to the event loop, or the UI cannot paint what has
              // arrived and the whole generation lands at once.
              await Future<void>.delayed(Duration.zero);
            }
          } finally {
            stream.release();
          }
        } finally {
          generator.release();
        }
      } finally {
        params.release();
      }
    } finally {
      tokenizer.release();
    }
  } finally {
    model.release();
  }
}

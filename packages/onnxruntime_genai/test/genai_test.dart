/// What the GenAI library does without a model.
///
/// Sequences, string arrays and tensors are handles a caller can build on
/// their own, so this exercises the wrappers, the ownership contract and the
/// error path without downloading anything. The model paths need a model and
/// live in the device and example suites.
library;

import 'package:onnxruntime_genai/onnxruntime_genai.dart';
import 'package:test/test.dart';

import 'src/genai_library.dart';

void main() {
  group('a sequences handle', () {
    test('starts empty and counts what is appended', () {
      final sequences = Sequences();
      addTearDown(sequences.release);

      expect(sequences.count(), 0);
      sequences.appendTokenSequence([1, 2, 3]);
      expect(sequences.count(), 1);
    });

    test('reports the length of a sequence it holds', () {
      final sequences = Sequences();
      addTearDown(sequences.release);

      sequences.appendTokenSequence([7, 8, 9, 10]);
      expect(sequences.getSequenceCount(0), 4);
    });

    test('a released handle refuses further use rather than crashing', () {
      final sequences = Sequences()..release();
      expect(sequences.isReleased, isTrue);
      expect(sequences.count, throwsA(isA<StateError>()));
    });

    test('releasing twice is refused, not ignored', () {
      final sequences = Sequences()..release();
      expect(sequences.release, throwsA(isA<StateError>()));
    });
  }, skip: skipWithoutGenAi);

  group('a string array', () {
    test('counts what is added', () {
      final strings = StringArray();
      addTearDown(strings.release);

      expect(strings.getCount(), 0);
      strings.addString('alpha');
      strings.addString('beta');
      expect(strings.getCount(), 2);
    });

    test('gives back what was put in', () {
      final strings = StringArray();
      addTearDown(strings.release);

      strings.addString('gamma');
      expect(strings.getString(0), 'gamma');
    });
  }, skip: skipWithoutGenAi);

  group('failure', () {
    test('a bad model path is an exception, not a crash', () {
      // The C API reports failure by returning a result object rather than a
      // code. This is the one path that proves check() reads the message and
      // releases the result rather than leaking it.
      expect(
        () => Model('/no/such/model'),
        throwsA(isA<GenAiException>()),
      );
    });

    test('the message says what went wrong', () {
      try {
        Model('/no/such/model');
        fail('expected a GenAiException');
      } on GenAiException catch (error) {
        expect(error.message, isNotEmpty);
        expect(error.toString(), contains('GenAiException'));
      }
    });
  }, skip: skipWithoutGenAi);
}

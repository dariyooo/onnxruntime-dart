/// What can be checked without downloading anything.
///
/// The models are between five megabytes and nearly three gigabytes, so the
/// runs themselves are not tested here. What is testable is everything around
/// them: that the catalogue describes real files, that the size arithmetic is
/// right, that the profile reader tells a fallback apart from a real run, and
/// that the tokenizer agrees with the vocabulary it is given.
library;

import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:onnxruntime_gallery/src/catalogue.dart';
import 'package:onnxruntime_gallery/src/diagnostics.dart';
import 'package:onnxruntime_gallery/src/store.dart';
import 'package:onnxruntime_gallery/src/store_web.dart';
import 'package:onnxruntime_gallery/src/text.dart';

void main() {
  group('the catalogue', () {
    test('describes every kind of model it says it does', () {
      final kinds = catalogue.map((spec) => spec.kind).toSet();
      expect(kinds, containsAll(ModelKind.values));
    });

    test('gives every model a distinct id, which is its directory', () {
      final ids = catalogue.map((spec) => spec.id).toList();
      expect(ids.toSet(), hasLength(ids.length));
    });

    test('names a source for every model, because none are from here', () {
      for (final spec in catalogue) {
        expect(spec.sourceUrl, startsWith('https://'), reason: spec.id);
        expect(spec.source, isNotEmpty, reason: spec.id);
      }
    });

    test('states a size for every file, so nothing downloads unannounced', () {
      for (final spec in catalogue) {
        expect(spec.files, isNotEmpty, reason: spec.id);
        for (final file in spec.files) {
          expect(file.bytes, greaterThan(0), reason: '${spec.id}/${file.name}');
          expect(file.url, startsWith('https://'), reason: file.name);
        }
        expect(
          spec.bytes,
          spec.files.fold<int>(0, (total, file) => total + file.bytes),
          reason: spec.id,
        );
      }
    });

    test('gives the classifiers their labels', () {
      // A classifier without synset.txt would run and then name every class
      // "class 413", which reads as a broken model rather than a missing file.
      for (final spec
          in catalogue.where((s) => s.kind == ModelKind.classifier)) {
        expect(
          spec.files.map((file) => file.name),
          contains('synset.txt'),
          reason: spec.id,
        );
      }
    });
  });

  group('where the models come from', () {
    // Offline on purpose: what is checked is which host each URL names, not
    // that the network is up. The hosts are not interchangeable and the wrong
    // one fails only in a browser, which is the slowest place to find out.
    test('never github.com/.../raw/, which a browser cannot fetch', () {
      // That path answers a cross-origin request with a 302 carrying an empty
      // Access-Control-Allow-Origin. An empty value is invalid, so the browser
      // refuses before following the redirect, and every download fails on the
      // web while working on every other platform.
      for (final spec in catalogue) {
        for (final file in spec.files) {
          expect(
            file.url,
            isNot(contains('github.com/onnx/models/raw/')),
            reason: '${spec.id}/${file.name}',
          );
        }
      }
    });

    test('model zoo files come from media, and plain files from raw', () {
      // media serves what Git LFS holds and 404s for anything else;
      // raw.githubusercontent serves the plain files and hands back a 132 byte
      // pointer for the LFS ones. Which applies is a property of the file.
      for (final spec in catalogue) {
        for (final file in spec.files) {
          if (!file.url.contains('githubusercontent')) continue;
          final lfs = file.name.endsWith('.onnx');
          expect(
            file.url,
            contains(lfs
                ? 'media.githubusercontent.com'
                : 'raw.githubusercontent.com'),
            reason:
                '${spec.id}/${file.name} is ${lfs ? '' : 'not '}stored in LFS',
          );
        }
      }
    });

    test('everything is fetched over https', () {
      for (final spec in catalogue) {
        for (final file in spec.files) {
          expect(file.url, startsWith('https://'), reason: file.name);
        }
      }
    });
  });

  group('sizes', () {
    test('read the way a person would write them', () {
      expect(humanBytes(512), '512 B');
      expect(humanBytes(4952956), '4.7 MB');
      expect(humanBytes(2722861056), '2.5 GB');
    });
  });

  group('the profile reader', () {
    late Directory scratch;

    setUp(() => scratch = Directory.systemTemp.createTempSync('gallery'));
    tearDown(() => scratch.deleteSync(recursive: true));

    File write(Object events) {
      final file = File('${scratch.path}/profile.json')
        ..writeAsStringSync(jsonEncode(events));
      return file;
    }

    test('counts the nodes each provider executed', () {
      final file = write([
        {
          'name': 'Conv',
          'args': {'provider': 'CPUExecutionProvider'}
        },
        {
          'name': 'Relu',
          'args': {'provider': 'CPUExecutionProvider'}
        },
        {
          'name': 'Gemm',
          'args': {'provider': 'JsExecutionProvider'}
        },
        {'name': 'model_run'},
      ]);

      final report = readProfile(
        file.path,
        wallTime: const Duration(milliseconds: 12),
        requested: const [],
      );

      expect(report.nodesByProvider, {
        'CPUExecutionProvider': 2,
        'JsExecutionProvider': 1,
      });
      expect(report.totalNodes, 3);
      // Largest first, so the principal provider is the one that did the work.
      expect(report.principal, 'CPUExecutionProvider');
    });

    test('says so when a requested provider took nothing', () {
      final file = write([
        {
          'args': {'provider': 'CPUExecutionProvider'}
        },
      ]);

      final report = readProfile(
        file.path,
        wallTime: Duration.zero,
        requested: const ['webgpu'],
      );

      expect(report.fellBack, isTrue);
      expect(report.warnings, isNotEmpty);
      expect(report.warnings.first, contains('webgpu'));
    });

    test('does not call a plain CPU run a fallback', () {
      final file = write([
        {
          'args': {'provider': 'CPUExecutionProvider'}
        },
      ]);

      final report = readProfile(
        file.path,
        wallTime: Duration.zero,
        requested: const [],
      );

      expect(report.fellBack, isFalse);
      expect(report.warnings, isEmpty);
    });

    test('reports a missing profile rather than inventing a provider', () {
      final report = readProfile(
        '${scratch.path}/there-is-no-such-file.json',
        wallTime: Duration.zero,
        requested: const ['webgpu'],
      );

      expect(report.nodesByProvider, isEmpty);
      expect(report.principal, isNull);
      expect(report.warnings.single, contains('no profile'));
    });
  });

  group('WordPiece', () {
    final tokenizer = WordPiece.parse([
      '[PAD]', // 0
      for (var i = 1; i < 100; i++) 'unused$i',
      '[UNK]', // 100
      '[CLS]', // 101
      '[SEP]', // 102
      'play', // 103
      '##ing', // 104
      'guitar', // 105
    ].join('\n'));

    test('brackets what it encodes, which is what the model expects', () {
      final ids = tokenizer.encode('guitar');
      expect(ids.first, 101);
      expect(ids.last, 102);
      expect(ids, [101, 105, 102]);
    });

    test('splits a word it does not know into pieces it does', () {
      expect(tokenizer.encode('playing'), [101, 103, 104, 102]);
    });

    test('gives up on a word as a whole rather than piece by piece', () {
      // What the training did: an unknown word is one unknown token, not a
      // run of them, so the length still matches the model's expectation.
      expect(tokenizer.encode('zzzz'), [101, 100, 102]);
    });

    test('keeps within the length it is given', () {
      final ids = tokenizer.encode('guitar ' * 200, maximum: 16);
      expect(ids, hasLength(16));
      expect(ids.last, 102);
    });
  });

  group('similarity', () {
    test('is one for the same direction and zero for a right angle', () {
      expect(cosineSimilarity([1, 2, 3], [2, 4, 6]), closeTo(1.0, 1e-9));
      expect(cosineSimilarity([1, 0], [0, 1]), closeTo(0.0, 1e-9));
    });

    test('is zero rather than a crash for an empty or degenerate vector', () {
      expect(cosineSimilarity(const [], const []), 0);
      expect(cosineSimilarity([0, 0], [1, 1]), 0);
    });
  });

  group('the in-memory store', () {
    // The web store, tested on the VM because it names nothing web: that is
    // what makes it the web half of the seam in the first place.
    late MemoryModelStore store;
    final spec = catalogue.first;

    setUp(() => store = MemoryModelStore());

    test('says a browser keeps nothing across a reload', () {
      expect(store.isPersistent, isFalse);
      expect(store.location, isNotEmpty);
    });

    test('offers no directory, which is what GenAI needs', () {
      // Not an oversight to fix later. GenAI reads a model directory rather
      // than bytes, so null here is what stops the card pretending.
      expect(store.directoryOf(spec), isNull);
    });

    test('holds a file and reads it back', () async {
      final file = spec.files.first;
      final bytes = Uint8List(file.bytes);
      await store.store(spec, file, bytes);

      expect(await store.read(spec, file.name), same(bytes));
      expect(await store.bytesHeld(spec), file.bytes);
    });

    test('is not complete until every file is held', () async {
      expect(await store.isComplete(spec), isFalse);
      for (final file in spec.files) {
        await store.store(spec, file, Uint8List(file.bytes));
      }
      expect(await store.isComplete(spec), isTrue);
      expect(await store.bytesTotal(), spec.bytes);
    });

    test('refuses a file that arrived the wrong length', () async {
      // The length is the only check available: a truncated download produces
      // bytes that decode as a model right up to where it stops.
      final file = spec.files.first;
      await store.store(spec, file, Uint8List(file.bytes - 1));
      expect(await store.isComplete(spec), isFalse);
      expect(await store.bytesHeld(spec), 0);
    });

    test('reading something never fetched says so', () {
      expect(() => store.read(spec, 'not-fetched.onnx'), throwsStateError);
    });

    test('evicting forgets a model and nothing else', () async {
      final other = catalogue[1];
      await store.store(
          spec, spec.files.first, Uint8List(spec.files.first.bytes));
      await store.store(
          other, other.files.first, Uint8List(other.files.first.bytes));

      await store.evict(spec);
      expect(await store.bytesHeld(spec), 0);
      expect(await store.bytesHeld(other), other.files.first.bytes);
    });
  });
}

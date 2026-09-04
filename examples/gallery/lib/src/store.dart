/// Where downloaded models live, and how they get there.
///
/// A model is fetched once and kept. The size is known before anything is
/// spent, reported as it is spent, and checked afterwards: a file that arrives
/// a different length than the catalogue promised is a different file, and
/// running it would mean demonstrating a model nobody described.
///
/// Where "kept" means depends on the platform, which is the one thing that
/// genuinely differs. On a desktop or a phone it is a directory, and a model
/// survives restarting the application. In a browser there is no directory to
/// write to, so it is held for as long as the tab lives and fetched again
/// after a reload. The app says which, rather than letting a reader assume the
/// download was wasted or that it was saved.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'catalogue.dart';
import 'store_open.dart';

/// How far along a download is.
class Progress {
  const Progress({
    required this.received,
    required this.total,
    required this.file,
  });

  final int received;
  final int total;

  /// Which file of a multi-file model is arriving, for the ones that have
  /// more than one.
  final String file;

  double get fraction => total == 0 ? 0 : received / total;
}

/// The models this application has fetched.
abstract class ModelStore {
  /// Opens the store this platform can offer.
  static Future<ModelStore> open() => openStore();

  /// Where the models are being kept, in words, for the UI to show.
  String get location;

  /// Whether a model kept here survives the application restarting.
  bool get isPersistent;

  /// The bytes of one of [spec]'s files, which must have been fetched.
  Future<Uint8List> read(ModelSpec spec, String name);

  /// A filesystem path to [spec]'s directory, where there is one.
  ///
  /// Null in a browser, and that is not a temporary gap: GenAI takes a
  /// directory rather than bytes, so a model that needs one cannot run there.
  String? directoryOf(ModelSpec spec);

  /// Whether every file [spec] needs is present and the right length.
  Future<bool> isComplete(ModelSpec spec);

  /// How much of [spec] is already held, so the app can say what is left.
  Future<int> bytesHeld(ModelSpec spec);

  /// Everything held, together.
  Future<int> bytesTotal();

  /// Forgets [spec].
  Future<void> evict(ModelSpec spec);

  /// Records one fetched file. Called by [fetch].
  Future<void> store(ModelSpec spec, RemoteFile file, Uint8List bytes);

  /// Fetches whatever [spec] is missing, reporting progress as it goes.
  ///
  /// Files already held at the right length are left alone, so a download
  /// interrupted after the third of eight files resumes at the fourth. The
  /// checking and the streaming are the same everywhere, which is why they are
  /// here rather than in each implementation.
  Stream<Progress> fetch(ModelSpec spec) async* {
    final total = spec.bytes;
    var done = await bytesHeld(spec);
    yield Progress(received: done, total: total, file: spec.files.first.name);

    final client = http.Client();
    try {
      for (final file in spec.files) {
        if (await _held(spec, file)) continue;

        final request = http.Request('GET', Uri.parse(file.url));
        final response = await client.send(request);
        if (response.statusCode != 200) {
          throw StateError(
            '${file.name}: the server answered ${response.statusCode}. The '
            'catalogue points at ${file.url}',
          );
        }

        final chunks = <List<int>>[];
        var received = 0;
        await for (final chunk in response.stream) {
          chunks.add(chunk);
          received += chunk.length;
          yield Progress(
            received: done + received,
            total: total,
            file: file.name,
          );
        }

        if (received != file.bytes) {
          throw StateError(
            '${file.name} arrived $received bytes, and the catalogue says '
            '${file.bytes}. That is a different file than the one described, '
            'so it has been discarded rather than kept.',
          );
        }

        final bytes = Uint8List(received);
        var offset = 0;
        for (final chunk in chunks) {
          bytes.setRange(offset, offset + chunk.length, chunk);
          offset += chunk.length;
        }
        await store(spec, file, bytes);

        done += file.bytes;
        yield Progress(received: done, total: total, file: file.name);
      }
    } finally {
      client.close();
    }
  }

  Future<bool> _held(ModelSpec spec, RemoteFile file) async {
    try {
      return (await read(spec, file.name)).length == file.bytes;
    } catch (_) {
      return false;
    }
  }
}

/// A size a person can read, in the units they would have used.
String humanBytes(int bytes) {
  const units = ['B', 'kB', 'MB', 'GB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return '${value < 10 && unit > 0 ? value.toStringAsFixed(1) : value.round()}'
      ' ${units[unit]}';
}

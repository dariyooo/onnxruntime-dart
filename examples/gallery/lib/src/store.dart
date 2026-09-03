/// Where downloaded models live, and how they get there.
///
/// A model is fetched once and kept. The size is known before anything is
/// spent, reported as it is spent, and checked afterwards: a file that arrives
/// a different length than the catalogue promised is a different file, and
/// running it would mean demonstrating a model nobody described.
///
/// Downloads go to a temporary name and are renamed on success, so an
/// interrupted download cannot be mistaken for a finished one the next time
/// the app starts.
library;

import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'catalogue.dart';

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

/// The on-disk copy of the models.
class ModelStore {
  ModelStore(this.root);

  /// Opens the store under the platform's application support directory.
  static Future<ModelStore> open() async {
    final base = await getApplicationSupportDirectory();
    final root = Directory(p.join(base.path, 'models'));
    await root.create(recursive: true);
    return ModelStore(root);
  }

  final Directory root;

  /// Where [spec]'s files live once fetched.
  Directory directoryFor(ModelSpec spec) =>
      Directory(p.join(root.path, spec.id));

  /// The main graph on disk, whether or not it is there yet.
  File modelFile(ModelSpec spec) =>
      File(p.join(directoryFor(spec).path, spec.model.name));

  /// Whether every file [spec] needs is present and the right length.
  ///
  /// Length rather than presence: a download killed partway leaves a file that
  /// exists, and opening it fails somewhere less obvious than here.
  Future<bool> isComplete(ModelSpec spec) async {
    for (final file in spec.files) {
      final onDisk = File(p.join(directoryFor(spec).path, file.name));
      if (!onDisk.existsSync()) return false;
      if (await onDisk.length() != file.bytes) return false;
    }
    return true;
  }

  /// How much of [spec] is already on disk, so the app can say what is left.
  Future<int> bytesHeld(ModelSpec spec) async {
    var held = 0;
    for (final file in spec.files) {
      final onDisk = File(p.join(directoryFor(spec).path, file.name));
      if (onDisk.existsSync() && await onDisk.length() == file.bytes) {
        held += file.bytes;
      }
    }
    return held;
  }

  /// Fetches whatever [spec] is missing, reporting progress as it goes.
  ///
  /// Files already present at the right length are left alone, so a download
  /// interrupted after the third of eight files resumes at the fourth.
  Stream<Progress> fetch(ModelSpec spec) async* {
    final directory = directoryFor(spec);
    await directory.create(recursive: true);

    final total = spec.bytes;
    var done = await bytesHeld(spec);
    yield Progress(received: done, total: total, file: spec.files.first.name);

    final client = http.Client();
    try {
      for (final file in spec.files) {
        final target = File(p.join(directory.path, file.name));
        if (target.existsSync() && await target.length() == file.bytes) {
          continue;
        }

        // A partial file from a previous run would otherwise be appended to.
        final partial = File('${target.path}.partial');
        if (partial.existsSync()) await partial.delete();

        final request = http.Request('GET', Uri.parse(file.url));
        final response = await client.send(request);
        if (response.statusCode != 200) {
          throw StateError(
            '${file.name}: the server answered ${response.statusCode}. The '
            'catalogue points at ${file.url}',
          );
        }

        final sink = partial.openWrite();
        var received = 0;
        try {
          await for (final chunk in response.stream) {
            sink.add(chunk);
            received += chunk.length;
            yield Progress(
              received: done + received,
              total: total,
              file: file.name,
            );
          }
        } finally {
          await sink.close();
        }

        final arrived = await partial.length();
        if (arrived != file.bytes) {
          await partial.delete();
          throw StateError(
            '${file.name} arrived $arrived bytes, and the catalogue says '
            '${file.bytes}. That is a different file than the one described, '
            'so it has been discarded rather than run.',
          );
        }

        await partial.rename(target.path);
        done += file.bytes;
        yield Progress(received: done, total: total, file: file.name);
      }
    } finally {
      client.close();
    }
  }

  /// Removes [spec] from disk.
  Future<void> evict(ModelSpec spec) async {
    final directory = directoryFor(spec);
    if (directory.existsSync()) await directory.delete(recursive: true);
  }

  /// What every model held on disk costs, together.
  Future<int> bytesOnDisk() async {
    if (!root.existsSync()) return 0;
    var total = 0;
    await for (final entry in root.list(recursive: true)) {
      if (entry is File) total += await entry.length();
    }
    return total;
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

/// Keeping models in a directory, which is what every platform but the web has.
///
/// A model fetched here survives the application closing, which is what makes
/// the larger ones bearable: Phi-3 is two and a half gigabytes and nobody
/// should pay that twice.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'catalogue.dart';
import 'store.dart';

/// Opens the store under the platform's application support directory.
Future<ModelStore> openStore() async {
  final base = await getApplicationSupportDirectory();
  final root = Directory(p.join(base.path, 'models'));
  await root.create(recursive: true);
  return FileModelStore(root);
}

/// The models, on disk.
class FileModelStore extends ModelStore {
  FileModelStore(this.root);

  final Directory root;

  @override
  String get location => root.path;

  @override
  bool get isPersistent => true;

  Directory _directory(ModelSpec spec) => Directory(p.join(root.path, spec.id));

  @override
  String? directoryOf(ModelSpec spec) => _directory(spec).path;

  File _file(ModelSpec spec, String name) =>
      File(p.join(_directory(spec).path, name));

  @override
  Future<Uint8List> read(ModelSpec spec, String name) =>
      _file(spec, name).readAsBytes();

  @override
  Future<void> store(ModelSpec spec, RemoteFile file, Uint8List bytes) async {
    await _directory(spec).create(recursive: true);
    // Written under a temporary name and renamed, so an interrupted write
    // cannot be mistaken for a finished one the next time the app starts.
    final partial = File('${_file(spec, file.name).path}.partial');
    await partial.writeAsBytes(bytes, flush: true);
    await partial.rename(_file(spec, file.name).path);
  }

  /// Length rather than presence: a download killed partway leaves a file that
  /// exists, and opening it fails somewhere less obvious than here.
  @override
  Future<bool> isComplete(ModelSpec spec) async {
    for (final file in spec.files) {
      final onDisk = _file(spec, file.name);
      if (!onDisk.existsSync()) return false;
      if (await onDisk.length() != file.bytes) return false;
    }
    return true;
  }

  @override
  Future<int> bytesHeld(ModelSpec spec) async {
    var held = 0;
    for (final file in spec.files) {
      final onDisk = _file(spec, file.name);
      if (onDisk.existsSync() && await onDisk.length() == file.bytes) {
        held += file.bytes;
      }
    }
    return held;
  }

  @override
  Future<int> bytesTotal() async {
    if (!root.existsSync()) return 0;
    var total = 0;
    await for (final entry in root.list(recursive: true)) {
      if (entry is File) total += await entry.length();
    }
    return total;
  }

  @override
  Future<void> evict(ModelSpec spec) async {
    final directory = _directory(spec);
    if (directory.existsSync()) await directory.delete(recursive: true);
  }
}

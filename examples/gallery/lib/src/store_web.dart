/// Keeping models in memory, which is what a browser leaves available.
///
/// Deliberately not IndexedDB. Persisting across reloads would be nicer, and it
/// is a fair amount of interop for a gain that only matters to the models a
/// browser can run at all, which are the small ones. A reload refetches, the UI
/// says so, and the alternative is a storage layer nobody is here to read.
///
/// Nothing in this file touches `dart:io`. That is the point of the seam: a web
/// build gets this one and never compiles the filesystem store.
library;

import 'dart:typed_data';

import 'catalogue.dart';
import 'store.dart';

/// Opens a store that lives as long as the tab.
Future<ModelStore> openStore() async => MemoryModelStore();

/// The models, in memory.
class MemoryModelStore extends ModelStore {
  final _held = <String, Uint8List>{};

  String _key(ModelSpec spec, String name) => '${spec.id}/$name';

  @override
  String get location => 'this browser tab';

  @override
  bool get isPersistent => false;

  /// Null, always. GenAI takes a directory rather than bytes, so a model that
  /// needs one cannot run here and the app says so rather than failing later.
  @override
  String? directoryOf(ModelSpec spec) => null;

  @override
  Future<Uint8List> read(ModelSpec spec, String name) async {
    final bytes = _held[_key(spec, name)];
    if (bytes == null) {
      throw StateError('$name has not been fetched into this tab');
    }
    return bytes;
  }

  @override
  Future<void> store(ModelSpec spec, RemoteFile file, Uint8List bytes) async {
    _held[_key(spec, file.name)] = bytes;
  }

  @override
  Future<bool> isComplete(ModelSpec spec) async => spec.files
      .every((file) => _held[_key(spec, file.name)]?.length == file.bytes);

  @override
  Future<int> bytesHeld(ModelSpec spec) async {
    var held = 0;
    for (final file in spec.files) {
      if (_held[_key(spec, file.name)]?.length == file.bytes) {
        held += file.bytes;
      }
    }
    return held;
  }

  @override
  Future<int> bytesTotal() async {
    var total = 0;
    for (final bytes in _held.values) {
      total += bytes.length;
    }
    return total;
  }

  @override
  Future<void> evict(ModelSpec spec) async {
    _held.removeWhere((key, _) => key.startsWith('${spec.id}/'));
  }
}

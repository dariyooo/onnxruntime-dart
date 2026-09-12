/// The tar reader, against archives built here rather than downloaded.
///
/// This is the step where a wrong file could be accepted quietly. It is a
/// hand-rolled reader, chosen so the hook has no dependency beyond the SDK,
/// and it had no test at all: every archive it had ever seen came from our own
/// release job, so it was only ever exercised on input that happened to be
/// well formed.
///
/// The archives here are written byte by byte. Using the real ones would test
/// the same happy path the release job already covers, and would say nothing
/// about a truncated download or an archive missing the file it was fetched
/// for.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:onnxruntime_hook/onnxruntime_hook.dart';
import 'package:test/test.dart';

/// One ustar header plus its contents, padded to the 512 byte block size.
List<int> _entry(String name, List<int> body) {
  final header = Uint8List(512);
  header.setRange(0, name.length, utf8.encode(name));
  // Size, octal, NUL terminated, in the field at offset 124.
  final size = body.length.toRadixString(8).padLeft(11, '0');
  header.setRange(124, 124 + 11, utf8.encode(size));
  header[135] = 0;
  // '0' is a regular file. Left as 0 by some writers, which means the same.
  header[156] = 0x30;

  final padded = (body.length + 511) & ~511;
  return [...header, ...body, ...List.filled(padded - body.length, 0)];
}

Uint8List _archive(Map<String, List<int>> entries) {
  final tar = <int>[
    for (final e in entries.entries) ..._entry(e.key, e.value),
    ...List.filled(1024, 0), // the two empty blocks that end an archive
  ];
  return Uint8List.fromList(gzip.encode(tar));
}

void main() {
  final library = utf8.encode('not really a library');
  final companion = utf8.encode('nor this');

  group('reading one file out of an archive', () {
    test('finds it by name', () {
      final archive = _archive({
        'libmat.so': companion,
        'libonnxruntime-genai.so': library,
      });
      expect(
        extractLibraryForTesting(archive, 'libonnxruntime-genai.so'),
        equals(library),
      );
    });

    test('ignores the directory it was stored under', () {
      // Archives from different producers differ here, and the name is
      // matched on its last segment for that reason.
      final archive = _archive({'lib/linux-x64/libonnxruntime.so': library});
      expect(
        extractLibraryForTesting(archive, 'libonnxruntime.so'),
        equals(library),
      );
    });

    test('refuses an archive that does not hold it, rather than guessing', () {
      // The failure that matters: a release published for one target being
      // installed for another must not return whatever it found instead.
      final archive = _archive({'libsomething-else.so': library});
      expect(
        () => extractLibraryForTesting(archive, 'libonnxruntime.so'),
        throwsA(isA<StateError>()),
      );
    });

    test('refuses a truncated archive rather than reading past the end', () {
      final full = _archive({'libonnxruntime.so': library});
      final cut = Uint8List.fromList(
        gzip.encode(gzip.decode(full).sublist(0, 512 + 4)),
      );
      expect(
        () => extractLibraryForTesting(cut, 'libonnxruntime.so'),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('reading a whole archive', () {
    test('returns every file, keyed by its own name', () {
      final archive = _archive({
        'libonnxruntime_providers_qnn.so': library,
        'libQnnHtp.so': companion,
        'LICENSE': utf8.encode('a licence'),
      });
      final entries = extractAllForTesting(archive);

      expect(
        entries.keys,
        containsAll(<String>[
          'libonnxruntime_providers_qnn.so',
          'libQnnHtp.so',
          'LICENSE',
        ]),
      );
      expect(entries['libQnnHtp.so'], equals(companion));
    });

    test('keeps the licence files that have to travel with the binaries', () {
      // The QNN archives carry them because redistribution is conditional on
      // it, so dropping them would leave that condition unmet on disk.
      final entries = extractAllForTesting(
        _archive({
          'libQnnHtp.so': companion,
          'Qualcomm_LICENSE.pdf': utf8.encode('%PDF'),
        }),
      );
      expect(entries.keys, contains('Qualcomm_LICENSE.pdf'));
    });

    test('an empty archive yields nothing rather than throwing', () {
      expect(extractAllForTesting(_archive({})), isEmpty);
    });
  });
}

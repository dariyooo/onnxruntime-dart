@TestOn('vm')

/// ORTCHAR_T is `wchar_t` on Windows and `char` elsewhere, so the same code
/// produces different bytes per platform. Both encodings are tested everywhere,
/// and the platform selection is checked against the platform actually running.
library;

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:onnxruntime_dart/src/ffi/ort_path.dart';
import 'package:test/test.dart';

void main() {
  // Paths ORT is plausibly handed, plus the cases that break naive encoders.
  const samples = [
    '',
    'model.onnx',
    r'C:\Users\dev\model.onnx',
    '/tmp/optimized model.onnx',
    'modèle.onnx',
    'モデル.onnx',
    'model\u{1F600}.onnx', // outside the BMP, so a UTF-16 surrogate pair
  ];

  for (final wide in [false, true]) {
    final encoding = wide ? 'utf-16' : 'utf-8';

    group('$encoding round trip', () {
      for (final sample in samples) {
        test('preserves ${sample.isEmpty ? '<empty>' : sample}', () {
          final arena = Arena();
          addTearDown(arena.releaseAll);

          final pointer = encodeOrtPath(sample, arena, wide: wide);
          expect(decodeOrtPath(pointer, wide: wide), sample);
        });
      }
    });
  }

  group('encoding', () {
    test('utf-8 writes one byte per ASCII character plus a NUL', () {
      final arena = Arena();
      addTearDown(arena.releaseAll);

      final pointer = encodeOrtPath('abc', arena, wide: false);
      final bytes = pointer.cast<Uint8>().asTypedList(4);
      expect(bytes, [0x61, 0x62, 0x63, 0x00]);
    });

    test('utf-16 writes two bytes per BMP character plus a NUL', () {
      final arena = Arena();
      addTearDown(arena.releaseAll);

      final pointer = encodeOrtPath('abc', arena, wide: true);
      final units = pointer.cast<Uint16>().asTypedList(4);
      expect(units, [0x61, 0x62, 0x63, 0x0000]);
    });

    test('utf-16 keeps surrogate pairs as two units', () {
      final arena = Arena();
      addTearDown(arena.releaseAll);

      // U+1F600 is D83D DE00 in UTF-16.
      final pointer = encodeOrtPath('\u{1F600}', arena, wide: true);
      final units = pointer.cast<Uint16>().asTypedList(3);
      expect(units, [0xD83D, 0xDE00, 0x0000]);
    });

    test('the two encodings genuinely differ', () {
      final arena = Arena();
      addTearDown(arena.releaseAll);

      final narrow = encodeOrtPath('ab', arena, wide: false).cast<Uint8>();
      final utf16 = encodeOrtPath('ab', arena, wide: true).cast<Uint8>();

      expect(narrow.asTypedList(3), [0x61, 0x62, 0x00]);
      expect(utf16.asTypedList(6), [0x61, 0x00, 0x62, 0x00, 0x00, 0x00]);
    });
  });

  group('platform selection', () {
    test('matches the platform actually running', () {
      expect(ortPathIsWide, Platform.isWindows);
      expect(ortPathUnitBytes, Platform.isWindows ? 2 : 1);
    });

    test('allocateOrtPath round trips through the platform encoding', () {
      final arena = Arena();
      addTearDown(arena.releaseAll);

      const path = 'モデル/model.onnx';
      expect(readOrtPath(allocateOrtPath(path, arena)), path);
    });

    test('wchar_t is 16-bit where we assume it is', () {
      // The whole problem exists because Windows chose 16-bit wchar_t. If a
      // platform ever disagrees, the bindings are silently wrong there.
      expect(sizeOf<WChar>(), Platform.isWindows ? 2 : 4);
    });
  });
}

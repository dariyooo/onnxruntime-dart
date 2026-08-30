/// One owner and one release, enforced. These run on the web too, because
/// ownership is shared code rather than something the FFI backend provides.
library;

import 'package:onnxruntime_dart/src/backend/types.dart';
import 'package:onnxruntime_dart/src/handle.dart';
import 'package:test/test.dart';

void main() {
  group('OrtHandle', () {
    test('releases exactly once, with the pointer it was given', () {
      final released = <OrtPtr>[];
      OrtHandle(const OrtPtr(0x1000), released.add, 'OrtSession').release();

      expect(released, [const OrtPtr(0x1000)]);
    });

    test('a second release throws instead of double-freeing', () {
      // Two owners is a bug worth failing on, not one to hide behind
      // idempotence: the second free would corrupt the heap.
      final handle = OrtHandle(const OrtPtr(1), (_) {}, 'OrtSession');
      handle.release();

      expect(
        handle.release,
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('already released'),
          ),
        ),
      );
    });

    test('use after release throws instead of reading freed memory', () {
      final handle = OrtHandle(const OrtPtr(1), (_) {}, 'OrtValue');
      handle.release();

      expect(
        () => handle.pointer,
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(contains('OrtValue'), contains('released')),
          ),
        ),
      );
    });

    test('refuses to own a null handle', () {
      // A create that failed returns null, and owning it would release null
      // later and hide the original failure.
      expect(
        () => OrtHandle(OrtPtr.nullPtr, (_) {}, 'OrtSession'),
        throwsArgumentError,
      );
    });

    test('releasing one does not disturb another', () {
      final released = <OrtPtr>[];
      final a = OrtHandle(const OrtPtr(1), released.add, 'OrtSession');
      final b = OrtHandle(const OrtPtr(2), released.add, 'OrtSession');

      a.release();
      expect(released, [const OrtPtr(1)]);
      expect(b.pointer, const OrtPtr(2));
      b.release();
      expect(released, [const OrtPtr(1), const OrtPtr(2)]);
    });

    test('says what it is and whether it is alive', () {
      final handle =
          OrtHandle(const OrtPtr(0xabc), (_) {}, 'OrtSessionOptions');
      expect(handle.toString(), 'OrtSessionOptions(0xabc)');
      expect(handle.isReleased, isFalse);

      handle.release();
      expect(handle.toString(), 'OrtSessionOptions(released)');
      expect(handle.isReleased, isTrue);
    });
  });
}

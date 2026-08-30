@TestOn('vm')

/// The annotation and the runtime error must agree. A member marked native-only
/// that silently works, or one that throws without being marked, is worse than
/// either alone.
library;

import 'package:onnxruntime_dart/onnxruntime_dart.dart';
import 'package:test/test.dart';

void main() {
  test('the error names the member and the reason', () {
    expect(
      () => unsupportedOnWeb(
          'Session.run', 'the wasm build exports no async run'),
      throwsA(
        isA<UnsupportedError>().having(
          (e) => e.message,
          'message',
          allOf(
            contains('Session.run'),
            contains('the wasm build exports no async run'),
          ),
        ),
      ),
    );
  });

  test('the annotation carries the same reason it throws with', () {
    const annotation = NativeOnly('the wasm build exports no async run');
    expect(
      () => unsupportedOnWeb('Session.run', annotation.reason),
      throwsA(
        isA<UnsupportedError>()
            .having((e) => e.message, 'message', contains(annotation.reason)),
      ),
    );
  });
}

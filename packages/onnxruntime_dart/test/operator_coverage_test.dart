@TestOn('vm')

/// Asserts the binary contains the operator domains we commit to shipping.
///
/// `test_matrix.py` checks we never pass a flag that trims operators, which is
/// a property of the build command. This checks the artifact that command
/// produced. The two catch different failures: a changed upstream default, or a
/// flag with a side effect, would slip past the first and be caught here.
///
/// ONNX Runtime resolves every operator at session initialisation, so a model
/// that loads is proof its kernels are registered. Models come from the pinned
/// submodule, so this reuses ORT's curated corpus rather than inventing one.
/// Whether those operators compute correctly is ORT's own test suite's job.
library;

import 'dart:typed_data';

import 'package:test/test.dart';

import 'src/ort_library.dart';
import 'src/session_probe.dart';
import 'src/test_models.dart';

void main() {
  group('operator domains', () {
    void expectLoads(String model, {required String domain}) {
      final result = tryLoadModel(readOrtTestModel(model));
      expect(
        result.ok,
        isTrue,
        reason: 'the $domain domain is missing from this build. '
            'ONNX Runtime reported: ${result.error}',
      );
    }

    test('ai.onnx standard operators', () {
      expectLoads('ort_minimal_e2e_test_data/test_voice_commands/model.onnx',
          domain: 'ai.onnx');
    });

    test('ai.onnx.ml classical machine learning kernels', () {
      // Dropped by --disable_ml_ops, which we never pass.
      expectLoads('zipmap_int64float.onnx', domain: 'ai.onnx.ml');
      expectLoads('tree_ensemble_as_tensor.onnx', domain: 'ai.onnx.ml');
    });

    test('com.microsoft contrib operators', () {
      // Dropped by --disable_contrib_ops. EmbedLayerNormalization is also one of
      // the fusion targets, so its absence would silently change graphs too.
      expectLoads('test_dangling_input_segment_ids.onnx',
          domain: 'com.microsoft');
    });

    // --enable_reduced_operator_type_support trims per-type kernels, so a model
    // per element type shows whether the build kept them all. Models are ORT's,
    // one per ONNX tensor type.
    for (final entry in dtypeModels.entries) {
      test('element type ${entry.key} is supported', () {
        final result = tryLoadModel(readSubmoduleFile(entry.value));
        expect(
          result.ok,
          isTrue,
          reason: 'this build cannot handle ${entry.key} tensors. '
              'ONNX Runtime reported: ${result.error}',
        );
      });
    }

    test('the probe reports failure, so the tests above mean something', () {
      // A probe that never returns false would make every domain test pass
      // regardless of what the binary actually contains.
      final result = tryLoadModel(Uint8List.fromList([0, 1, 2, 3, 4, 5, 6, 7]));
      expect(result.ok, isFalse);
      expect(result.error, isNotEmpty);
    });
  }, skip: skipWithoutOrt);
}

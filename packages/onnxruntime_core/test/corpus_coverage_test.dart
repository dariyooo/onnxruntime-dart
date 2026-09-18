@TestOn('vm')

/// Loads every model in the pinned submodule and asserts that no operator we
/// commit to shipping is missing from the build.
///
/// Session initialisation resolves every operator, so a model that fails with
/// "is not a registered function/op" names a kernel this binary does not have.
/// Sweeping the whole corpus turns that into comprehensive coverage: if a build
/// dropped contrib ops, `Attention` and `SkipLayerNormalization` would appear
/// here immediately rather than waiting for a user to hit them.
///
/// This replaces running ORT's own `onnx_test_runner`, which would need the
/// unit-test target built on all fifteen configurations to answer a question we
/// do not have: whether ORT computes correctly. That is ORT's to verify. Ours is
/// whether our build configuration kept everything.
///
/// The sweep is session creation only, no inference, and takes under a second.
library;

import 'dart:io';

import 'package:test/test.dart';

import 'src/ort_library.dart';
import 'src/paths.dart';
import 'src/session_probe.dart';

/// Operators legitimately absent from a build of ours.
///
/// Anything not listed here that fails to resolve is a regression.
const _expectedAbsent = {
  // Training, explicitly out of scope.
  'AdamWOptimizer', 'ATen', 'BitmaskDropoutGrad', 'ConcatTraining',
  'DropoutGrad', 'SoftmaxCrossEntropyLossGrad',
  'SoftmaxCrossEntropyLossInternal', 'YieldOp',

  // Distributed inference, not built.
  'Recv', 'Send',

  // Fixtures for ORT's own custom-op tests. They exist to be unregistered.
  'CustomGemmFloat8E4M3FN', 'CustomOpOne', 'CustomOpOneFloat8',
  'Fake_FunctionOp', 'Foo', 'FooBar', 'FooBar_Attr', 'Fuse', 'OptionalOp',
  'VariadicNode',

  // Provided by separate libraries, not the core: onnxruntime-extensions and
  // the OpenVINO execution provider.
  'OpenVINO_Wrapper', 'StringLower',
};

/// Skip anything large enough to make the sweep slow. Coverage comes from the
/// hundreds of small models, not the few big ones.
const _maxModelBytes = 20 * 1024 * 1024;

void main() {
  group('operator corpus', () {
    late final _SweepResult sweep;

    setUpAll(() => sweep = _sweepCorpus());

    test('the sweep actually examined the corpus', () {
      // Guards every assertion below: a sweep that found no models would pass
      // them all.
      expect(sweep.attempted, greaterThan(500));
      expect(sweep.loaded, greaterThan(700));
    });

    test('no operator we ship is missing', () {
      final unexpected = sweep.unregistered.difference(_expectedAbsent);
      expect(
        unexpected,
        isEmpty,
        reason:
            'this build is missing operators. If these are genuinely out of '
            'scope, add them to _expectedAbsent with a reason. Otherwise the '
            'build configuration dropped kernels it should have kept.',
      );
    });

    test('contrib and classical-ML operators resolve across the corpus', () {
      // Narrower than the check above and worth stating separately, because
      // these are the two domains a build flag can silently remove.
      const canaries = {
        'Attention',
        'SkipLayerNormalization',
        'EmbedLayerNormalization',
        'MatMulNBits',
        'BiasGelu',
        'FusedMatMul',
        'TreeEnsembleClassifier',
        'ZipMap',
        'LabelEncoder',
      };
      expect(sweep.unregistered.intersection(canaries), isEmpty);
    });
  }, skip: skipWithoutOrt);
}

typedef _SweepResult = ({int attempted, int loaded, Set<String> unregistered});

_SweepResult _sweepCorpus() {
  final root = Directory(fromRoot('third_party/onnxruntime'));
  final unregistered = <String>{};
  var attempted = 0;
  var loaded = 0;

  for (final entry in root.listSync(recursive: true, followLinks: false)) {
    if (entry is! File || !entry.path.endsWith('.onnx')) continue;
    if (entry.statSync().size > _maxModelBytes) continue;

    attempted++;
    final result = tryLoadModel(entry.readAsBytesSync());
    if (result.ok) {
      loaded++;
      continue;
    }
    final name = _unregisteredOperator(result.error!);
    if (name != null) unregistered.add(name);
  }
  return (attempted: attempted, loaded: loaded, unregistered: unregistered);
}

/// Extracts the operator name from a "not a registered function/op" message,
/// or null when the failure was something else. Invalid models, missing
/// external data and unsupported opsets are not our concern here.
String? _unregisteredOperator(String message) {
  const marker = 'is not a registered function/op';
  final end = message.indexOf(marker);
  if (end < 0) return null;

  // The message reads "... Fatal error: <domain>:<Op>(<version>) is not ...".
  final head = message.substring(0, end).trimRight();
  final token = head.split(RegExp(r'\s+')).last;
  final name = token.split(':').last.replaceAll(RegExp(r'\(-?\d+\)$'), '');
  return name.isEmpty ? null : name;
}

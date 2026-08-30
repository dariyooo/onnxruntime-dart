@TestOn('vm')

/// The keys are generated because ONNX Runtime declares them with internal
/// linkage, which ffigen cannot see. Nothing else notices if the generator
/// silently drops some, so the count is checked against the headers.
library;

import 'dart:io';

import 'package:onnxruntime_dart/src/bindings/config_keys.g.dart';
import 'package:test/test.dart';

import 'src/paths.dart';

int _declaredIn(String header) => RegExp(
      r'static\s+const\s+char\*\s+const\s+k\w+\s*=\s*"[^"]*"\s*;',
    )
        .allMatches(
          File(
            fromRoot(
              'third_party/onnxruntime/include/onnxruntime/core/session/$header',
            ),
          ).readAsStringSync(),
        )
        .length;

void main() {
  group('generated configuration keys', () {
    test('every key in the headers is generated', () {
      expect(
        SessionConfig.all.length,
        _declaredIn('onnxruntime_session_options_config_keys.h'),
      );
      expect(
        RunConfig.all.length,
        _declaredIn('onnxruntime_run_options_config_keys.h'),
      );
      expect(
        EnvConfig.all.length,
        _declaredIn('onnxruntime_env_config_keys.h'),
      );
    });

    test('no two constants collapsed onto one name', () {
      for (final group in [SessionConfig.all, RunConfig.all, EnvConfig.all]) {
        expect(group.toSet().length, group.length);
      }
    });

    test('values are the strings the runtime expects, not the C names', () {
      expect(SessionConfig.disablePrepacking, 'session.disable_prepacking');
      expect(
          RunConfig.all, contains('disable_synchronize_execution_providers'));
      expect(EnvConfig.allowVirtualDevices, 'allow_virtual_devices');
    });

    test('prefixes are stripped without mangling runs of capitals', () {
      // kOrtSessionOptionsEnableQuantQDQ, not enableQuantQdq.
      expect(SessionConfig.all, contains('session.disable_prepacking'));
      expect(
        SessionConfig.enableQuantQDQCleanup,
        'session.enable_quant_qdq_cleanup',
      );
    });
  });
}

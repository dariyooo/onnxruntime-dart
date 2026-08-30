@TestOn('vm')

/// Verifies the generated bindings against a real ONNX Runtime binary.
///
/// ffigen emits `OrtApi` as a struct of 425 function pointers. If a field order
/// or type is wrong, every call dispatches to the wrong function and the failure
/// surfaces far from its cause. Nothing else in the suite catches that, so these
/// tests exercise the struct layout rather than any ORT behaviour.
library;

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:onnxruntime_dart/src/bindings/ort_bindings.g.dart';
import 'package:test/test.dart';

import 'src/ort_library.dart';
import 'src/paths.dart';

void main() {
  group('generated bindings', () {
    late final OrtBindings bindings;
    late final Pointer<OrtApiBase> apiBase;

    setUpAll(() {
      bindings = OrtBindings(openOrtLibrary());
      apiBase = bindings.OrtGetApiBase();
    });

    test('OrtGetApiBase is the only exported free function and resolves', () {
      expect(apiBase, isNot(nullptr));
    });

    test('GetVersionString dispatches correctly', () {
      // Calling through a function pointer at a generated struct offset. A wrong
      // offset returns garbage or crashes, so matching the submodule's version
      // proves the layout up to this field.
      final version =
          apiBase.ref.GetVersionString.asFunction<Pointer<Char> Function()>()();
      final expected = File(fromRoot('third_party/onnxruntime/VERSION_NUMBER'))
          .readAsStringSync()
          .trim();

      expect(version.cast<Utf8>().toDartString(), expected);
    });

    test('the binary accepts our generated ORT_API_VERSION', () {
      final api = apiBase.ref.GetApi
          .asFunction<Pointer<OrtApi> Function(int)>()(ORT_API_VERSION);

      expect(
        api,
        isNot(nullptr),
        reason: 'the runtime rejected API version $ORT_API_VERSION, so the '
            'bindings and the binary disagree on the ABI',
      );
    });

    test('version negotiation actually negotiates', () {
      // Guards against the previous test passing on a runtime that returns a
      // pointer regardless of the version asked for.
      final api = apiBase.ref.GetApi
          .asFunction<Pointer<OrtApi> Function(int)>()(ORT_API_VERSION + 900);

      expect(api, nullptr);
    });

    test('OrtApi is a solid block of function pointers', () {
      // 425 pointers and nothing else. A stray non-pointer field would shift
      // every subsequent offset.
      expect(sizeOf<OrtApi>() % sizeOf<Pointer<Void>>(), 0);
      expect(sizeOf<OrtApi>() ~/ sizeOf<Pointer<Void>>(), 425);
    });

    test('function pointers we depend on are populated', () {
      final api = apiBase.ref.GetApi
          .asFunction<Pointer<OrtApi> Function(int)>()(ORT_API_VERSION)
          .ref;

      // Spread across the struct, so a truncated or shifted layout shows up.
      expect(api.CreateEnv, isNot(nullptr));
      expect(api.CreateSessionFromArray, isNot(nullptr));
      expect(api.CreateTensorWithDataAsOrtValue, isNot(nullptr));
      expect(api.Run, isNot(nullptr));
      expect(api.RunAsync, isNot(nullptr));
      expect(api.RunWithBinding, isNot(nullptr));
      expect(api.AddFreeDimensionOverrideByName, isNot(nullptr));
      expect(api.ReleaseStatus, isNot(nullptr));
    });

    test('an error round-trips through OrtStatus', () {
      // Exercises the create/read/release triple that every fallible call uses.
      final api = apiBase.ref.GetApi
          .asFunction<Pointer<OrtApi> Function(int)>()(ORT_API_VERSION)
          .ref;

      final message = 'deliberate'.toNativeUtf8();
      final status = api.CreateStatus.asFunction<
          Pointer<OrtStatus> Function(int, Pointer<Char>)>()(
        OrtErrorCode.ORT_INVALID_ARGUMENT.value,
        message.cast(),
      );
      calloc.free(message);

      expect(status, isNot(nullptr));
      final code =
          api.GetErrorCode.asFunction<int Function(Pointer<OrtStatus>)>()(
              status);
      final text = api.GetErrorMessage.asFunction<
          Pointer<Char> Function(Pointer<OrtStatus>)>()(status);

      expect(code, OrtErrorCode.ORT_INVALID_ARGUMENT.value);
      expect(text.cast<Utf8>().toDartString(), 'deliberate');

      api.ReleaseStatus.asFunction<void Function(Pointer<OrtStatus>)>()(status);
    });
  }, skip: skipWithoutOrt);
}

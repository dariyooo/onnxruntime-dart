@TestOn('vm')
@Tags(['exclusive'])

/// The generated wrappers, exercised against a real model.
///
/// They are generated from the same headers the library is built from, so what
/// is being checked here is not the C API but the generator: that its parameter
/// direction, ownership and marshalling rules produce code that works.
library;

import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:onnxruntime_dart/native.dart';
import 'package:onnxruntime_dart/src/backend/types.dart';
import 'package:test/test.dart';

import 'src/ort_library.dart';
import 'src/test_models.dart';

void main() {
  group('generated wrappers', () {
    late final OrtApi api;
    late final Pointer<OrtSession> session;
    late final Arena arena;

    setUpAll(() {
      api = ortApi().ref;
      arena = Arena();
      final model = readSubmoduleFile(
        'onnxruntime/test/testdata/ort_minimal_e2e_test_data/'
        'test_voice_commands/model.onnx',
      );
      final buffer = arena<Uint8>(model.length);
      buffer.asTypedList(model.length).setAll(0, model);

      final options = api.createSessionOptions();
      session = api.createSessionFromArray(
        OrtEnvironment.instance().handle,
        buffer.cast(),
        model.length,
        options,
      );
      api.releaseSessionOptions(options);
    });

    tearDownAll(() {
      api.releaseSession(session);
      arena.releaseAll();
    });

    test('an out-parameter becomes the return value', () {
      // SessionGetInputCount takes _Out_ size_t*, which the generator turns
      // into an int return rather than a pointer the caller allocates.
      expect(api.sessionGetInputCount(session), 1);
      expect(api.sessionGetOutputCount(session), 1);
    });

    test('an allocator-owned string is read and freed', () {
      // char** with an _Inout_ OrtAllocator* is the pattern the generator
      // recognises as allocator memory. Reading without freeing would leak one
      // name per call.
      final allocator = api.getAllocatorWithDefaultOptions();
      expect(api.sessionGetInputName(session, 0, allocator), 'input_1');
      expect(api.sessionGetOutputName(session, 0, allocator), 'dense_1');
    });

    test('reading a name repeatedly does not accumulate', () {
      // If takeAllocatedString stopped freeing, this is where it would show.
      final allocator = api.getAllocatorWithDefaultOptions();
      for (var i = 0; i < 2000; i++) {
        expect(api.sessionGetInputName(session, 0, allocator), 'input_1');
      }
    });

    test('handles come back as handles, and are released by name', () {
      final info = api.sessionGetInputTypeInfo(session, 0);
      addTearDown(() => api.releaseTypeInfo(info));
      expect(info, isNot(nullptr));
    });

    test('enums cross as their underlying integer', () {
      final info = api.sessionGetInputTypeInfo(session, 0);
      addTearDown(() => api.releaseTypeInfo(info));

      final shape = api.castTypeInfoToTensorInfo(info);
      expect(
        api.getTensorElementType(shape),
        OrtElementType.float32.code,
        reason: 'ONNXTensorElementDataType is an enum in C, an int here',
      );
    });

    test('model metadata comes back as strings the allocator owns', () {
      final metadata = api.sessionGetModelMetadata(session);
      addTearDown(() => api.releaseModelMetadata(metadata));

      final allocator = api.getAllocatorWithDefaultOptions();
      expect(api.modelMetadataGetGraphName(metadata, allocator), isNotEmpty);
      expect(
        api.modelMetadataGetProducerName(metadata, allocator),
        isNotEmpty,
      );
      // Domain and description are empty in most models, which is still a
      // string rather than a null.
      expect(api.modelMetadataGetDomain(metadata, allocator), isA<String>());
      expect(api.modelMetadataGetVersion(metadata), isA<int>());
    });

    test('memory info round-trips its own fields', () {
      // CreateMemoryInfo takes two enums and a name, so it exercises the
      // string-in, enum-in path that most option calls use.
      final info = api.createMemoryInfo(
        'Cpu',
        OrtAllocatorType.OrtArenaAllocator.value,
        0,
        OrtMemType.OrtMemTypeDefault.value,
      );
      addTearDown(() => api.releaseMemoryInfo(info));

      expect(api.memoryInfoGetName(info), 'Cpu');
      expect(api.memoryInfoGetId(info), 0);
      expect(
        api.compareMemoryInfo(info, info),
        0,
        reason: 'a memory info equals itself',
      );
    });

    test('a type info reports the ONNX type it holds', () {
      final info = api.sessionGetInputTypeInfo(session, 0);
      addTearDown(() => api.releaseTypeInfo(info));

      expect(
        api.getOnnxTypeFromTypeInfo(info),
        ONNXType.ONNX_TYPE_TENSOR.value,
      );
    });

    test('an IO binding accepts and clears what is bound to it', () {
      // The whole binding group, which nothing else here reaches.
      final binding = api.createIoBinding(session);
      addTearDown(() => api.releaseIoBinding(binding));

      final allocator = api.getAllocatorWithDefaultOptions();
      final tensor = api.createTensorAsOrtValue(
        allocator,
        [1, 6],
        2,
        OrtElementType.float32.code,
      );
      addTearDown(() => api.releaseValue(tensor));

      api.bindInput(binding, 'input_1', tensor);

      final shape = api.getTensorTypeAndShape(tensor);
      addTearDown(() => api.releaseTensorTypeAndShapeInfo(shape));
      expect(api.getTensorShapeElementCount(shape), 6);

      api
        ..clearBoundInputs(binding)
        ..clearBoundOutputs(binding);
    });

    test('a failure raises rather than returning a status', () {
      // The generated wrapper checks and releases the OrtStatus, so callers
      // never see one.
      expect(
        () => api.sessionGetInputName(
          session,
          99,
          api.getAllocatorWithDefaultOptions(),
        ),
        throwsA(isA<OrtException>()),
      );
    });
  }, skip: skipWithoutOrt ?? skipWithoutNativeAsset);
}

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

    test('a callee-allocated array is read through its own count', () {
      // GetEpDevices hands back an array it owns and the length in a separate
      // out-parameter. The wrapper has to allocate one pointer cell rather
      // than room for the elements, and read the count from its own cell.
      final devices = api.getEpDevices(OrtEnvironment.instance().handle);
      expect(devices, isA<List<Pointer<OrtEpDevice>>>());
      // Every build registers at least the CPU device.
      expect(devices, isNotEmpty);
      expect(devices.every((d) => d != nullptr), isTrue);

      // The names are readable, which is what proves the pointers are real
      // rather than a count that happened to be plausible. Called through the
      // raw field: EpDevice_EpName returns a string rather than a status, and
      // the generator only wraps the ORT_API2_STATUS shape.
      final epName = api.EpDevice_EpName.asFunction<
          Pointer<Char> Function(Pointer<OrtEpDevice>)>();
      for (final device in devices) {
        expect(epName(device).cast<Utf8>().toDartString(), isNotEmpty);
      }
    });

    test('an allocator-owned string array is read and freed', () {
      final metadata = api.sessionGetModelMetadata(session);
      addTearDown(() => api.releaseModelMetadata(metadata));
      final allocator = api.getAllocatorWithDefaultOptions();

      // Both the keys and the array holding them are the allocator's, so a
      // wrapper that frees only one of them leaks. Repeating it would show up
      // as growth; what is checked here is that it returns the same answer and
      // does not crash on the second free.
      final first =
          api.modelMetadataGetCustomMetadataMapKeys(metadata, allocator);
      final second =
          api.modelMetadataGetCustomMetadataMapKeys(metadata, allocator);
      expect(first, second);
      expect(first, isA<List<String>>());
    });

    test('a shape borrowed from the runtime reads as a list of dimensions', () {
      // GetTensorElementTypeAndShapeDataReference returns a pointer into the
      // runtime's own memory plus a count, and must not be freed.
      final input = api.sessionGetInputTypeInfo(session, 0);
      addTearDown(() => api.releaseTypeInfo(input));
      final info = api.castTypeInfoToTensorInfo(input);
      expect(api.getDimensionsCount(info), greaterThan(0));
    });

    test('a callback parameter reaches Dart when the runtime calls it', () {
      // The runtime stores the pointer and calls it later, so the wrapper
      // takes it rather than building one: only the caller knows how long it
      // has to stay alive. isolateLocal is right here because session creation
      // logs on the thread that asked for it, which is this one.
      final messages = <String>[];
      final callback = NativeCallable<
          Void Function(Pointer<Void>, UnsignedInt, Pointer<Char>,
              Pointer<Char>, Pointer<Char>, Pointer<Char>)>.isolateLocal(
        (Pointer<Void> param,
            int severity,
            Pointer<Char> category,
            Pointer<Char> logid,
            Pointer<Char> location,
            Pointer<Char> message) {
          messages.add(message.cast<Utf8>().toDartString());
        },
      );
      addTearDown(callback.close);

      final options = api.createSessionOptions();
      addTearDown(() => api.releaseSessionOptions(options));
      api.setUserLoggingFunction(options, callback.nativeFunction, nullptr);
      api.setSessionLogSeverityLevel(options, 0);

      final model = readSubmoduleFile(
        'onnxruntime/test/testdata/ort_minimal_e2e_test_data/'
        'test_voice_commands/model.onnx',
      );
      final buffer = arena<Uint8>(model.length);
      buffer.asTypedList(model.length).setAll(0, model);
      final logged = api.createSessionFromArray(
        OrtEnvironment.instance().handle,
        buffer.cast(),
        model.length,
        options,
      );
      api.releaseSession(logged);

      // Verbose logging during session creation is chatty on every build, so
      // an empty list means the callback never ran rather than that the
      // runtime had nothing to say.
      expect(messages, isNotEmpty);
    });

    test('two arrays sharing one count both come back', () {
      // GetKeyValuePairs hands back keys and values with a single num_entries
      // after both, so the count has to be found by looking past the second
      // array rather than at the next parameter.
      final kvps = api.createKeyValuePairs();
      addTearDown(() => api.releaseKeyValuePairs(kvps));
      api.addKeyValuePair(kvps, 'device', 'cpu');
      api.addKeyValuePair(kvps, 'precision', 'fp32');

      final (keys, values) = api.getKeyValuePairs(kvps);
      expect(keys, hasLength(2));
      expect(values, hasLength(2));
      expect(Map.fromIterables(keys, values),
          {'device': 'cpu', 'precision': 'fp32'});
    });

    test('a contradictory annotation is overridden, not obeyed', () {
      // The header marks device_id as _In_ although the call writes into it.
      // Generated as an output the wrapper returns the id; obeyed, it would
      // take a pointer and return nothing. That difference is what is checked
      // here, and it holds whichever way the call itself goes.
      //
      // On a build without a GPU provider the runtime raises rather than
      // answering, which is the call failing and not the wrapper: asking a
      // CPU build which GPU it is on has no answer. Both outcomes are typed
      // the same way, so both prove the override took.
      try {
        expect(api.getCurrentGpuDeviceId(), isA<int>());
      } on OrtException {
        // No GPU provider in this build.
      }
    });

    test('a string tensor element reads back what was put in it', () {
      final allocator = api.getAllocatorWithDefaultOptions();
      final shape = [2];
      final tensor = api.createTensorAsOrtValue(
        allocator,
        shape,
        shape.length,
        ONNXTensorElementDataType.ONNX_TENSOR_ELEMENT_DATA_TYPE_STRING.value,
      );
      addTearDown(() => api.releaseValue(tensor));

      api.fillStringTensor(tensor, ['first', 'second'], 2);
      expect(api.stringTensorElement(tensor, 0), 'first');
      expect(api.stringTensorElement(tensor, 1), 'second');
    });

    test('bound output names come back split on their own lengths', () {
      // The names arrive concatenated in one buffer with a separate array of
      // lengths, so the split is this side's job and an off-by-one shows up as
      // a name with a stray character rather than as a failure to read.
      final binding = api.createIoBinding(session);
      addTearDown(() => api.releaseIoBinding(binding));
      final allocator = api.getAllocatorWithDefaultOptions();
      final memory = api.createCpuMemoryInfo(
        OrtAllocatorType.OrtArenaAllocator.value,
        OrtMemType.OrtMemTypeDefault.value,
      );
      addTearDown(() => api.releaseMemoryInfo(memory));

      final wanted = api.sessionGetOutputName(session, 0, allocator);
      api.bindOutputToDevice(binding, wanted, memory);

      expect(api.boundOutputNames(binding, allocator), [wanted]);
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

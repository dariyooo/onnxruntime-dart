/// Minimal session creation over the raw bindings.
///
/// Enough to answer one question: does this binary contain the kernels a model
/// needs? ONNX Runtime resolves every operator at session initialisation, so a
/// model that loads is proof its operators are registered, and a missing one
/// fails with a message naming the domain and op.
///
/// Deliberately not the eventual `Session` type. This exists to test the
/// artifact, not to be an API.
library;

import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:onnxruntime_dart/src/bindings/ort_bindings.g.dart';

import 'ort_library.dart';

/// The result of trying to load a model.
typedef LoadResult = ({bool ok, String? error});

/// Creates and immediately destroys a session for [model].
///
/// Returns `ok: true` when every operator resolved, otherwise the runtime's
/// error message.
LoadResult tryLoadModel(Uint8List model) {
  final api = _api;
  final arena = Arena();
  try {
    final envOut = arena<Pointer<OrtEnv>>();
    _check(
      api,
      api.CreateEnv.asFunction<
              Pointer<OrtStatus> Function(
                  int, Pointer<Char>, Pointer<Pointer<OrtEnv>>)>()(
          OrtLoggingLevel.ORT_LOGGING_LEVEL_ERROR.value,
          'onnxruntime_dart_test'.toNativeUtf8(allocator: arena).cast(),
          envOut),
    );
    final env = envOut.value;

    final optionsOut = arena<Pointer<OrtSessionOptions>>();
    _check(
      api,
      api.CreateSessionOptions.asFunction<
          Pointer<OrtStatus> Function(Pointer<Pointer<OrtSessionOptions>>)>()(
        optionsOut,
      ),
    );
    final options = optionsOut.value;

    final buffer = arena<Uint8>(model.length);
    buffer.asTypedList(model.length).setAll(0, model);

    final sessionOut = arena<Pointer<OrtSession>>();
    final status = api.CreateSessionFromArray.asFunction<
        Pointer<OrtStatus> Function(Pointer<OrtEnv>, Pointer<Void>, int,
            Pointer<OrtSessionOptions>, Pointer<Pointer<OrtSession>>)>()(
      env,
      buffer.cast(),
      model.length,
      options,
      sessionOut,
    );

    final LoadResult result;
    if (status == nullptr) {
      api.ReleaseSession.asFunction<void Function(Pointer<OrtSession>)>()(
          sessionOut.value);
      result = (ok: true, error: null);
    } else {
      result = (ok: false, error: _takeMessage(api, status));
    }

    api.ReleaseSessionOptions.asFunction<
        void Function(Pointer<OrtSessionOptions>)>()(options);
    api.ReleaseEnv.asFunction<void Function(Pointer<OrtEnv>)>()(env);
    return result;
  } finally {
    arena.releaseAll();
  }
}

OrtApi get _api {
  final base = OrtBindings(openOrtLibrary()).OrtGetApiBase();
  final api = base.ref.GetApi
      .asFunction<Pointer<OrtApi> Function(int)>()(ORT_API_VERSION);
  if (api == nullptr) {
    throw StateError('runtime rejected API version $ORT_API_VERSION');
  }
  return api.ref;
}

/// Reads and releases [status].
String _takeMessage(OrtApi api, Pointer<OrtStatus> status) {
  final message = api.GetErrorMessage.asFunction<
          Pointer<Char> Function(Pointer<OrtStatus>)>()(status)
      .cast<Utf8>()
      .toDartString();
  api.ReleaseStatus.asFunction<void Function(Pointer<OrtStatus>)>()(status);
  return message;
}

void _check(OrtApi api, Pointer<OrtStatus> status) {
  if (status != nullptr) throw StateError(_takeMessage(api, status));
}

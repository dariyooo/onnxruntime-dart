/// The FFI implementation of the backend boundary.
///
/// Thin over the generated bindings. Where a boundary method is one C call it
/// forwards; where the C API needs a sequence, the sequence is here so the
/// shared code does not have to know the difference between this and the
/// WebAssembly backend.
library;

import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../bindings/ort_bindings.g.dart';
import '../ffi/environment.dart';
import '../ffi/status.dart';
import 'types.dart';

/// Calls ONNX Runtime through `dart:ffi`.
final class FfiCalls {
  FfiCalls(this._environment);

  factory FfiCalls.instance() => FfiCalls(OrtEnvironment.instance());

  final OrtEnvironment _environment;

  OrtApi get _api => _environment.api;

  OrtPtr createSessionOptions() => _withArena((arena) {
        final out = arena<Pointer<OrtSessionOptions>>();
        checkStatus(
          _api,
          _api.CreateSessionOptions.asFunction<
              Pointer<OrtStatus> Function(
                  Pointer<Pointer<OrtSessionOptions>>)>()(out),
        );
        return OrtPtr(out.value.address);
      });

  void releaseSessionOptions(OrtPtr options) => _api.ReleaseSessionOptions
          .asFunction<void Function(Pointer<OrtSessionOptions>)>()(
        Pointer.fromAddress(options.address),
      );

  int addSessionConfigEntry(OrtPtr options, String key, String value) =>
      _withArena((arena) {
        checkStatus(
          _api,
          _api.AddSessionConfigEntry.asFunction<
              Pointer<OrtStatus> Function(
                Pointer<OrtSessionOptions>,
                Pointer<Char>,
                Pointer<Char>,
              )>()(
            Pointer.fromAddress(options.address),
            key.toNativeUtf8(allocator: arena).cast(),
            value.toNativeUtf8(allocator: arena).cast(),
          ),
        );
        return 0;
      });

  /// Creates a session from bytes already in memory.
  ///
  /// The runtime copies the model during initialisation, so the buffer does not
  /// have to outlive this call.
  OrtPtr createSession(Uint8List model, OrtPtr options) => _withArena((arena) {
        final buffer = arena<Uint8>(model.length);
        buffer.asTypedList(model.length).setAll(0, model);

        final out = arena<Pointer<OrtSession>>();
        checkStatus(
          _api,
          _api.CreateSessionFromArray.asFunction<
              Pointer<OrtStatus> Function(
                Pointer<OrtEnv>,
                Pointer<Void>,
                int,
                Pointer<OrtSessionOptions>,
                Pointer<Pointer<OrtSession>>,
              )>()(
            _environment.handle,
            buffer.cast(),
            model.length,
            Pointer.fromAddress(options.address),
            out,
          ),
        );
        return OrtPtr(out.value.address);
      });

  void releaseSession(OrtPtr session) =>
      _api.ReleaseSession.asFunction<void Function(Pointer<OrtSession>)>()(
        Pointer.fromAddress(session.address),
      );

  (int inputs, int outputs) inputOutputCount(OrtPtr session) =>
      _withArena((arena) {
        final handle = Pointer<OrtSession>.fromAddress(session.address);
        final inputs = arena<Size>();
        final outputs = arena<Size>();
        checkStatus(
          _api,
          _api.SessionGetInputCount.asFunction<
              Pointer<OrtStatus> Function(
                  Pointer<OrtSession>, Pointer<Size>)>()(handle, inputs),
        );
        checkStatus(
          _api,
          _api.SessionGetOutputCount.asFunction<
              Pointer<OrtStatus> Function(
                  Pointer<OrtSession>, Pointer<Size>)>()(handle, outputs),
        );
        return (inputs.value, outputs.value);
      });

  /// Name, element type and shape for one input or output.
  ///
  /// Seven C calls where WebAssembly has one, and two of them release something.
  /// The name comes from the allocator and leaks unless freed, and the type info
  /// is a handle of its own.
  OrtTensorMeta inputOutputMetadata(
    OrtPtr session,
    int index, {
    required bool input,
  }) =>
      _withArena((arena) {
        final handle = Pointer<OrtSession>.fromAddress(session.address);
        final allocator = _defaultAllocator(arena);

        final namePointer = arena<Pointer<Char>>();
        checkStatus(
          _api,
          (input ? _api.SessionGetInputName : _api.SessionGetOutputName)
              .asFunction<
                  Pointer<OrtStatus> Function(
                    Pointer<OrtSession>,
                    int,
                    Pointer<OrtAllocator>,
                    Pointer<Pointer<Char>>,
                  )>()(handle, index, allocator, namePointer),
        );
        final name = namePointer.value.cast<Utf8>().toDartString();
        // Allocator memory, so it is ours to free.
        _api.AllocatorFree.asFunction<
            Pointer<OrtStatus> Function(Pointer<OrtAllocator>,
                Pointer<Void>)>()(allocator, namePointer.value.cast());

        final typeInfoOut = arena<Pointer<OrtTypeInfo>>();
        checkStatus(
          _api,
          (input ? _api.SessionGetInputTypeInfo : _api.SessionGetOutputTypeInfo)
              .asFunction<
                  Pointer<OrtStatus> Function(
                    Pointer<OrtSession>,
                    int,
                    Pointer<Pointer<OrtTypeInfo>>,
                  )>()(handle, index, typeInfoOut),
        );

        try {
          final shapeOut = arena<Pointer<OrtTensorTypeAndShapeInfo>>();
          checkStatus(
            _api,
            _api.CastTypeInfoToTensorInfo.asFunction<
                Pointer<OrtStatus> Function(
                  Pointer<OrtTypeInfo>,
                  Pointer<Pointer<OrtTensorTypeAndShapeInfo>>,
                )>()(typeInfoOut.value, shapeOut),
          );
          final shapeInfo = shapeOut.value;

          final elementType = arena<UnsignedInt>();
          checkStatus(
            _api,
            _api.GetTensorElementType.asFunction<
                Pointer<OrtStatus> Function(
                  Pointer<OrtTensorTypeAndShapeInfo>,
                  Pointer<UnsignedInt>,
                )>()(shapeInfo, elementType),
          );

          final rank = arena<Size>();
          checkStatus(
            _api,
            _api.GetDimensionsCount.asFunction<
                Pointer<OrtStatus> Function(
                  Pointer<OrtTensorTypeAndShapeInfo>,
                  Pointer<Size>,
                )>()(shapeInfo, rank),
          );

          final dims = arena<Int64>(rank.value == 0 ? 1 : rank.value);
          if (rank.value > 0) {
            checkStatus(
              _api,
              _api.GetDimensions.asFunction<
                  Pointer<OrtStatus> Function(
                    Pointer<OrtTensorTypeAndShapeInfo>,
                    Pointer<Int64>,
                    int,
                  )>()(shapeInfo, dims, rank.value),
            );
          }

          return OrtTensorMeta(
            name: name,
            elementType: OrtElementType.fromCode(elementType.value),
            shape: List.unmodifiable([
              for (var i = 0; i < rank.value; i++) dims[i],
            ]),
          );
        } finally {
          // Owned by us regardless of how the reads went.
          _api.ReleaseTypeInfo.asFunction<
              void Function(Pointer<OrtTypeInfo>)>()(typeInfoOut.value);
        }
      });

  /// The default CPU allocator, which the runtime owns and we must not release.
  Pointer<OrtAllocator> _defaultAllocator(Arena arena) {
    final out = arena<Pointer<OrtAllocator>>();
    checkStatus(
      _api,
      _api.GetAllocatorWithDefaultOptions.asFunction<
          Pointer<OrtStatus> Function(Pointer<Pointer<OrtAllocator>>)>()(out),
    );
    return out.value;
  }
}

T _withArena<T>(T Function(Arena arena) body) {
  final arena = Arena();
  try {
    return body(arena);
  } finally {
    arena.releaseAll();
  }
}

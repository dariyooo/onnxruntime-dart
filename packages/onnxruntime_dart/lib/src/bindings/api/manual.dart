/// The calls the generator cannot express, written by hand.
///
/// Three shapes defeat it, and all three are about a buffer's lifetime rather
/// than its type:
///
///   * out-parameters the call writes into that must outlive the call, so an
///     arena scoped to it would free them first;
///   * the ask-then-fill pattern, where the same call is made twice, once for
///     a size and once for the contents;
///   * allocations returned to the caller that have their own release call.
///
/// Anything here is listed in `unmapped.txt` with the reason it is not
/// generated, so the two stay in step. Each wrapper names the C call it stands
/// for on its first line, the same as a generated one, so both are found the
/// same way.
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../ort_bindings.g.dart';
import 'options.g.dart';
import 'tensor.g.dart';
import 'support.dart';

/// Hand-written wrappers, alongside the generated ones on the same struct.
extension ManualApi on OrtApi {
  /// `Run`
  ///
  /// Runs [session], returning the outputs it produced. Not generated: `Run`
  /// takes its outputs as an array it writes into, and a generated wrapper
  /// would free that array before returning.
  List<Pointer<OrtValue>> runAndTakeOutputs(
    Pointer<OrtSession> session,
    Pointer<OrtRunOptions> runOptions,
    List<String> inputNames,
    List<Pointer<OrtValue>> inputs,
    List<String> outputNames,
  ) =>
      withArena((arena) {
        final outputs =
            arena<Pointer<OrtValue>>(_atLeastOne(outputNames.length));
        for (var i = 0; i < outputNames.length; i++) {
          outputs[i] = nullptr;
        }

        checkOrtStatus(
          Run.asFunction<
              Pointer<OrtStatus> Function(
                Pointer<OrtSession>,
                Pointer<OrtRunOptions>,
                Pointer<Pointer<Char>>,
                Pointer<Pointer<OrtValue>>,
                int,
                Pointer<Pointer<Char>>,
                int,
                Pointer<Pointer<OrtValue>>,
              )>()(
            session,
            runOptions,
            nativeStrings(inputNames, arena),
            nativePointers(inputs, arena),
            inputs.length,
            nativeStrings(outputNames, arena),
            outputNames.length,
            outputs,
          ),
        );

        return [for (var i = 0; i < outputNames.length; i++) outputs[i]];
      });

  /// `GetStringTensorContent`
  ///
  /// Reads a string tensor as one buffer plus per-element offsets. Not
  /// generated: the call writes into a buffer the caller sizes and provides.
  (Uint8List content, List<int> offsets) stringTensorContent(
    Pointer<OrtValue> value,
    int byteLength,
    int count,
  ) =>
      withArena((arena) {
        final buffer = arena<Uint8>(_atLeastOne(byteLength));
        final offsets = arena<Size>(_atLeastOne(count));
        checkOrtStatus(
          GetStringTensorContent.asFunction<
              Pointer<OrtStatus> Function(
                Pointer<OrtValue>,
                Pointer<Void>,
                int,
                Pointer<Size>,
                int,
              )>()(value, buffer.cast(), byteLength, offsets, count),
        );
        return (
          Uint8List.fromList(buffer.asTypedList(byteLength)),
          [for (var i = 0; i < count; i++) offsets[i]],
        );
      });

  /// `GetSessionConfigEntry`
  ///
  /// The value of a config entry, or null when it is not set.
  ///
  /// `getSessionConfigEntry` is generated and does the same two-call read, but
  /// an entry that was never set is an error there. This asks first and
  /// answers null, which is what a caller reading an optional setting wants.
  String? sessionConfigEntry(Pointer<OrtSessionOptions> options, String key) =>
      withArena((arena) {
        if (hasSessionConfigEntry(options, key) == 0) return null;

        final name = key.toNativeUtf8(allocator: arena).cast<Char>();
        final size = arena<Size>()..value = 0;
        final get = GetSessionConfigEntry.asFunction<
            Pointer<OrtStatus> Function(
              Pointer<OrtSessionOptions>,
              Pointer<Char>,
              Pointer<Char>,
              Pointer<Size>,
            )>();

        // The first call reports the size it needs, including the terminator,
        // and fails because the buffer is not there yet.
        final status = get(options, name, nullptr, size);
        if (status != nullptr) {
          ReleaseStatus.asFunction<void Function(Pointer<OrtStatus>)>()(status);
        }

        final buffer = arena<Char>(_atLeastOne(size.value));
        checkOrtStatus(get(options, name, buffer, size));
        return buffer.cast<Utf8>().toDartString();
      });

  /// `GetAvailableProviders`, `ReleaseAvailableProviders`
  ///
  /// The execution providers this build was compiled with. Not generated: the
  /// array comes from the runtime and has its own release call, which this
  /// makes rather than leaving to the caller. There is no wrapper for the
  /// release on its own, because there is no way to reach the array without
  /// going through here.
  List<String> availableProviders() => withArena((arena) {
        final out = arena<Pointer<Pointer<Char>>>();
        final count = arena<Int>();
        checkOrtStatus(
          GetAvailableProviders.asFunction<
              Pointer<OrtStatus> Function(
                Pointer<Pointer<Pointer<Char>>>,
                Pointer<Int>,
              )>()(out, count),
        );

        try {
          return [
            for (var i = 0; i < count.value; i++)
              out.value[i].cast<Utf8>().toDartString(),
          ];
        } finally {
          checkOrtStatus(
            ReleaseAvailableProviders.asFunction<
                Pointer<OrtStatus> Function(Pointer<Pointer<Char>>, int)>()(
              out.value,
              count.value,
            ),
          );
        }
      });

  /// `GetBoundOutputValues`
  ///
  /// The values bound as outputs, in binding order. Not generated: the array
  /// comes from [allocator] and must be freed separately from the values.
  List<Pointer<OrtValue>> boundOutputValues(
    Pointer<OrtIoBinding> binding,
    Pointer<OrtAllocator> allocator,
  ) =>
      withArena((arena) {
        final out = arena<Pointer<Pointer<OrtValue>>>();
        final count = arena<Size>();
        checkOrtStatus(
          GetBoundOutputValues.asFunction<
              Pointer<OrtStatus> Function(
                Pointer<OrtIoBinding>,
                Pointer<OrtAllocator>,
                Pointer<Pointer<Pointer<OrtValue>>>,
                Pointer<Size>,
              )>()(binding, allocator, out, count),
        );

        try {
          return [for (var i = 0; i < count.value; i++) out.value[i]];
        } finally {
          // The array only, not the values: those belong to the caller now.
          checkOrtStatus(
            AllocatorFree.asFunction<
                Pointer<OrtStatus> Function(
                  Pointer<OrtAllocator>,
                  Pointer<Void>,
                )>()(allocator, out.value.cast()),
          );
        }
      });

  /// `GetStringTensorElement`
  ///
  /// One string out of a string tensor. Not generated: the buffer is sized
  /// from a second call, `GetStringTensorElementLength`, so the length is not
  /// something the caller can be asked for.
  String stringTensorElement(Pointer<OrtValue> value, int index) =>
      withArena((arena) {
        final length = getStringTensorElementLength(value, index);
        final buffer = arena<Uint8>(_atLeastOne(length));
        checkOrtStatus(
          GetStringTensorElement.asFunction<
              Pointer<OrtStatus> Function(
                Pointer<OrtValue>,
                int,
                int,
                Pointer<Void>,
              )>()(value, length, index, buffer.cast()),
        );
        // Not NUL-terminated: the length is the whole of it.
        return utf8.decode(buffer.asTypedList(length));
      });

  /// `GetBoundOutputNames`
  ///
  /// The names bound to [binding], in the order they were bound. Not
  /// generated: the names come back concatenated in one buffer with their
  /// lengths in a second array, and both are the allocator's to free.
  List<String> boundOutputNames(
    Pointer<OrtIoBinding> binding,
    Pointer<OrtAllocator> allocator,
  ) =>
      withArena((arena) {
        final buffer = arena<Pointer<Char>>();
        final lengths = arena<Pointer<Size>>();
        final count = arena<Size>();
        checkOrtStatus(
          GetBoundOutputNames.asFunction<
              Pointer<OrtStatus> Function(
                Pointer<OrtIoBinding>,
                Pointer<OrtAllocator>,
                Pointer<Pointer<Char>>,
                Pointer<Pointer<Size>>,
                Pointer<Size>,
              )>()(binding, allocator, buffer, lengths, count),
        );

        // Nothing bound means nothing was allocated, so there is nothing to
        // free either.
        if (count.value == 0) return const [];

        final free = AllocatorFree.asFunction<
            Pointer<OrtStatus> Function(
                Pointer<OrtAllocator>, Pointer<Void>)>();
        try {
          final bytes = buffer.value.cast<Uint8>();
          final names = <String>[];
          var offset = 0;
          for (var i = 0; i < count.value; i++) {
            final length = lengths.value[i];
            names.add(utf8.decode(bytes
                .asTypedList(offset + length)
                .sublist(offset, offset + length)));
            offset += length;
          }
          return names;
        } finally {
          free(allocator, buffer.value.cast());
          free(allocator, lengths.value.cast());
        }
      });

  /// `GetResizedStringTensorElementBuffer`
  ///
  /// Resizes one element of a string tensor and hands back the buffer to write
  /// it into. Not generated: the annotation says `_Inout_` on what is an
  /// out-parameter, and what comes back points into the tensor rather than
  /// being the caller's to free.
  ///
  /// The pointer is valid until the tensor is released or the same element is
  /// resized again.
  Pointer<Char> resizedStringTensorElementBuffer(
    Pointer<OrtValue> value,
    int index,
    int lengthInBytes,
  ) =>
      withArena((arena) {
        final buffer = arena<Pointer<Char>>();
        checkOrtStatus(
          GetResizedStringTensorElementBuffer.asFunction<
              Pointer<OrtStatus> Function(
                Pointer<OrtValue>,
                int,
                int,
                Pointer<Pointer<Char>>,
              )>()(value, index, lengthInBytes, buffer),
        );
        return buffer.value;
      });

  /// `UseCooIndices`
  ///
  /// Gives a sparse tensor its COO indices without copying them. Not
  /// generated: the tensor keeps [indices] rather than copying it, so the
  /// allocation must outlive the tensor and an arena would free it as this
  /// call returns. Allocate it with `malloc`, or from an arena that outlives
  /// the tensor, and free it after the tensor is released.
  void useCooIndices(
    Pointer<OrtValue> value,
    Pointer<Int64> indices,
    int count,
  ) =>
      checkOrtStatus(
        UseCooIndices.asFunction<
            Pointer<OrtStatus> Function(
              Pointer<OrtValue>,
              Pointer<Int64>,
              int,
            )>()(value, indices, count),
      );

  /// `UseCsrIndices`
  ///
  /// Gives a sparse tensor its CSR indices without copying them. Both arrays
  /// are kept rather than copied, with the same lifetime rule as
  /// [useCooIndices].
  void useCsrIndices(
    Pointer<OrtValue> value,
    Pointer<Int64> inner,
    int innerCount,
    Pointer<Int64> outer,
    int outerCount,
  ) =>
      checkOrtStatus(
        UseCsrIndices.asFunction<
            Pointer<OrtStatus> Function(
              Pointer<OrtValue>,
              Pointer<Int64>,
              int,
              Pointer<Int64>,
              int,
            )>()(value, inner, innerCount, outer, outerCount),
      );

  /// `UseBlockSparseIndices`
  ///
  /// Gives a sparse tensor its block-sparse indices without copying them. The
  /// shape is copied, the indices are kept, with the same lifetime rule as
  /// [useCooIndices].
  void useBlockSparseIndices(
    Pointer<OrtValue> value,
    List<int> indicesShape,
    Pointer<Int32> indices,
  ) =>
      withArena((arena) {
        checkOrtStatus(
          UseBlockSparseIndices.asFunction<
              Pointer<OrtStatus> Function(
                Pointer<OrtValue>,
                Pointer<Int64>,
                int,
                Pointer<Int32>,
              )>()(
            value,
            nativeInt64s(indicesShape, arena),
            indicesShape.length,
            indices,
          ),
        );
      });
}

/// A zero-length allocation is not meaningful, and a model can have no inputs.
int _atLeastOne(int count) => count == 0 ? 1 : count;

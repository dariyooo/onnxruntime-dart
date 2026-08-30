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

import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../ort_bindings.g.dart';
import 'options.g.dart';
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
  /// The value of a config entry, or null when it is not set. Not generated:
  /// the call is made twice, once for the size and once for the contents.
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

  /// `GetAvailableProviders`
  ///
  /// The execution providers this build was compiled with. Not generated: the
  /// array comes from the runtime and has its own release call.
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
}

/// A zero-length allocation is not meaningful, and a model can have no inputs.
int _atLeastOne(int count) => count == 0 ? 1 : count;

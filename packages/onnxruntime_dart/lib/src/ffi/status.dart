/// Turns `OrtStatus` into Dart exceptions.
library;

import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../bindings/ort_bindings.g.dart';

/// An error reported by ONNX Runtime.
final class OrtException implements Exception {
  OrtException(this.code, this.message);

  /// One of the `OrtErrorCode` values.
  final int code;

  final String message;

  @override
  String toString() => 'OrtException($code): $message';
}

/// Throws if [status] is an error, releasing it either way.
///
/// Every fallible call returns an OrtStatus that the caller owns, so releasing
/// on both paths is the only correct handling.
void checkStatus(OrtApi api, Pointer<OrtStatus> status) {
  if (status == nullptr) return;

  final code =
      api.GetErrorCode.asFunction<int Function(Pointer<OrtStatus>)>()(status);
  final message = api.GetErrorMessage.asFunction<
          Pointer<Char> Function(Pointer<OrtStatus>)>()(status)
      .cast<Utf8>()
      .toDartString();
  api.ReleaseStatus.asFunction<void Function(Pointer<OrtStatus>)>()(status);

  throw OrtException(code, message);
}

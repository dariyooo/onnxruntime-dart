/// Errors the package raises.
///
/// Shared code, deliberately: an exception type that only exists on one
/// platform cannot be caught in code meant to run on both.
library;

/// An error reported by ONNX Runtime.
final class OrtException implements Exception {
  OrtException(this.code, this.message);

  /// One of the `OrtErrorCode` values.
  final int code;

  final String message;

  @override
  String toString() => 'OrtException($code): $message';
}

/// Thrown when the loaded runtime does not support the bound API version.
final class OrtAbiMismatch implements Exception {
  OrtAbiMismatch(this.requiredApiVersion, this.runtimeVersion);

  final int requiredApiVersion;
  final String runtimeVersion;

  @override
  String toString() =>
      'ONNX Runtime $runtimeVersion does not support API version '
      '$requiredApiVersion, which these bindings were generated against.';
}

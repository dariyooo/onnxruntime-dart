/// Types crossing the boundary between the shared code and a backend.
///
/// None of them mention `dart:ffi`, so everything above the boundary compiles
/// for the web as well as for native.
library;

import 'dart:typed_data';

/// An opaque handle into backend memory.
///
/// Native, this is a pointer address. On the web it is an offset into the
/// emscripten heap. Either way it is an integer, which is why it can be the one
/// currency the shared code deals in.
extension type const OrtPtr(int address) {
  static const OrtPtr nullPtr = OrtPtr(0);

  bool get isNull => address == 0;
}

/// The element types ONNX Runtime understands.
///
/// The values are fixed by `ONNXTensorElementDataType` in the C API and by
/// `TensorProto.DataType` in the ONNX format, which agree.
enum OrtElementType {
  undefined(0, null),
  float32(1, 4),
  uint8(2, 1),
  int8(3, 1),
  uint16(4, 2),
  int16(5, 2),
  int32(6, 4),
  int64(7, 8),
  string(8, null),
  boolean(9, 1),
  float16(10, 2),
  float64(11, 8),
  uint32(12, 4),
  uint64(13, 8),
  complex64(14, 8),
  complex128(15, 16),
  bfloat16(16, 2);

  const OrtElementType(this.code, this.byteWidth);

  /// The value the C API uses.
  final int code;

  /// Bytes per element, or null where the encoding is not fixed width.
  final int? byteWidth;

  static OrtElementType fromCode(int code) => values.firstWhere(
        (t) => t.code == code,
        orElse: () =>
            throw ArgumentError.value(code, 'code', 'unknown element type'),
      );
}

/// What a session says about one of its inputs or outputs.
final class OrtTensorMeta {
  const OrtTensorMeta({
    required this.name,
    required this.elementType,
    required this.shape,
  });

  final String name;
  final OrtElementType elementType;

  /// One entry per dimension. `-1` marks a dimension the model decides at run
  /// time, which is usually batch size.
  final List<int> shape;

  /// Whether any dimension is decided at run time.
  bool get isDynamic => shape.contains(-1);

  @override
  String toString() => '$name ${elementType.name} $shape';
}

/// A view of a tensor's contents, borrowed from the backend.
///
/// [data] is only valid while the tensor that produced it is alive. Copy it if
/// it needs to outlive that.
final class OrtTensorView {
  const OrtTensorView({
    required this.elementType,
    required this.shape,
    required this.data,
  });

  final OrtElementType elementType;
  final List<int> shape;
  final Uint8List data;

  /// Number of elements implied by [shape]. A scalar has one.
  int get elementCount => shape.fold(1, (a, b) => a * b);
}

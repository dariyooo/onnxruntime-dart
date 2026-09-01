/// Types crossing the boundary between the shared code and a backend.
///
/// None of them mention `dart:ffi`, so everything above the boundary compiles
/// for the web as well as for native.
library;

import 'dart:typed_data';

/// Whether this platform has 64-bit integer lists.
///
/// False only on dart2js, where an `int` is a JavaScript number and therefore
/// a double. Written as a comparison rather than a library check because
/// dart2wasm is also the web and does have them.
const _hasInt64Lists = !identical(1, 1.0);

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

/// How much ONNX Runtime rewrites the graph before running it.
///
/// The values are fixed by `GraphOptimizationLevel` in the C API. More
/// optimisation costs time when the session is created and saves it on every
/// run, so the default is worth changing only when loading time dominates.
enum OrtOptimizationLevel {
  none(0),
  basic(1),
  extended(2),
  layout(3),
  all(99);

  const OrtOptimizationLevel(this.code);

  /// The value the C API uses.
  final int code;
}

/// Whether independent branches of a graph run at the same time.
///
/// The values are fixed by `ExecutionMode` in the C API. Parallel uses the
/// inter-op thread pool, and only helps a graph that actually branches.
enum OrtExecutionMode {
  sequential(0),
  parallel(1);

  const OrtExecutionMode(this.code);

  /// The value the C API uses.
  final int code;
}

/// How much ONNX Runtime logs.
///
/// The values are fixed by `OrtLoggingLevel` in the C API.
enum OrtLogLevel {
  verbose(0),
  info(1),
  warning(2),
  error(3),
  fatal(4);

  const OrtLogLevel(this.code);

  /// The value the C API uses.
  final int code;
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

  /// The contents as the list matching [elementType].
  ///
  /// Throws [StateError] when the type is not what was asked for, rather than
  /// reinterpreting the bytes: reading an int64 tensor as float32 produces
  /// numbers, and none of them mean anything.
  Float32List get float32s =>
      _typed(OrtElementType.float32, (b, o, n) => b.asFloat32List(o, n));

  Float64List get float64s =>
      _typed(OrtElementType.float64, (b, o, n) => b.asFloat64List(o, n));

  Int8List get int8s =>
      _typed(OrtElementType.int8, (b, o, n) => b.asInt8List(o, n));

  Uint8List get uint8s =>
      _typed(OrtElementType.uint8, (b, o, n) => b.asUint8List(o, n));

  Int16List get int16s =>
      _typed(OrtElementType.int16, (b, o, n) => b.asInt16List(o, n));

  Uint16List get uint16s =>
      _typed(OrtElementType.uint16, (b, o, n) => b.asUint16List(o, n));

  Int32List get int32s =>
      _typed(OrtElementType.int32, (b, o, n) => b.asInt32List(o, n));

  Uint32List get uint32s =>
      _typed(OrtElementType.uint32, (b, o, n) => b.asUint32List(o, n));

  /// Throws on a JavaScript build, where there is no 64-bit integer list.
  ///
  /// Use [data] there and decode the bytes yourself. The tensor itself is
  /// fine, and int64 is common in ONNX models, so this is about reading the
  /// values out rather than about the model.
  Int64List get int64s {
    _refuseWithoutInt64('int64s');
    return _typed(OrtElementType.int64, (b, o, n) => b.asInt64List(o, n));
  }

  /// Throws on a JavaScript build, for the same reason as [int64s].
  Uint64List get uint64s {
    _refuseWithoutInt64('uint64s');
    return _typed(OrtElementType.uint64, (b, o, n) => b.asUint64List(o, n));
  }

  /// Refuses before the typed view is built, so the message names the reason.
  ///
  /// dart2js would otherwise throw its own `Int64List not supported`, which
  /// says what failed but not what to do instead.
  void _refuseWithoutInt64(String accessor) {
    if (!_hasInt64Lists) {
      throw UnsupportedError(
        'OrtTensorView.$accessor: this is a JavaScript build, where Dart '
        'numbers are doubles and there is no Int64List. The tensor is '
        'readable, just not as 64-bit integers: use `view.data` for the raw '
        'little-endian bytes and decode them. Compiling to WebAssembly '
        'instead gives you real 64-bit integers and this accessor works.',
      );
    }
  }

  /// A boolean tensor, which ONNX stores one byte per element.
  List<bool> get bools => [
        for (final byte in _typed(
          OrtElementType.boolean,
          (b, o, n) => b.asUint8List(o, n),
        ))
          byte != 0,
      ];

  /// The raw bits of a half-float tensor, which Dart has no type for.
  Uint16List get float16Bits =>
      _typed(OrtElementType.float16, (b, o, n) => b.asUint16List(o, n));

  /// Checks the type before building the view, so a mismatch reports the type
  /// rather than a length that only looks wrong.
  T _typed<T>(
    OrtElementType expected,
    T Function(ByteBuffer buffer, int offset, int length) view,
  ) {
    if (elementType != expected) {
      throw StateError(
        'this is a ${elementType.name} tensor, not ${expected.name}',
      );
    }
    return view(data.buffer, data.offsetInBytes, elementCount);
  }
}

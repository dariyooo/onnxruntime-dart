/// Reads the ONNX `TensorProto` messages that ship as reference test vectors.
///
/// Ground truth for inference results, so it decodes the vectors independently
/// of the code under test.
///
/// No protobuf dependency. Only four fields matter: `dims` (1), `data_type` (2),
/// `name` (8) and `raw_data` (9). Unknown fields are skipped by wire type.
library;

import 'dart:convert';
import 'dart:typed_data';

/// Values of ONNX `TensorProto.DataType`, numerically identical to
/// `ONNXTensorElementDataType` in the C API.
extension type const OnnxDataType(int code) {
  static const undefined = OnnxDataType(0);
  static const float32 = OnnxDataType(1);
  static const uint8 = OnnxDataType(2);
  static const int8 = OnnxDataType(3);
  static const uint16 = OnnxDataType(4);
  static const int16 = OnnxDataType(5);
  static const int32 = OnnxDataType(6);
  static const int64 = OnnxDataType(7);
  static const string = OnnxDataType(8);
  static const boolean = OnnxDataType(9);
  static const float16 = OnnxDataType(10);
  static const float64 = OnnxDataType(11);
  static const uint32 = OnnxDataType(12);
  static const uint64 = OnnxDataType(13);
  static const complex64 = OnnxDataType(14);
  static const complex128 = OnnxDataType(15);
  static const bfloat16 = OnnxDataType(16);

  /// Null for types with no fixed width (`undefined`, `string`).
  int? get byteWidth => switch (this) {
        uint8 || int8 || boolean => 1,
        uint16 || int16 || float16 || bfloat16 => 2,
        float32 || int32 || uint32 => 4,
        float64 || int64 || uint64 || complex64 => 8,
        complex128 => 16,
        _ => null,
      };

  String get name => switch (this) {
        undefined => 'undefined',
        float32 => 'float32',
        uint8 => 'uint8',
        int8 => 'int8',
        uint16 => 'uint16',
        int16 => 'int16',
        int32 => 'int32',
        int64 => 'int64',
        string => 'string',
        boolean => 'bool',
        float16 => 'float16',
        float64 => 'float64',
        uint32 => 'uint32',
        uint64 => 'uint64',
        complex64 => 'complex64',
        complex128 => 'complex128',
        bfloat16 => 'bfloat16',
        _ => 'unknown($code)',
      };
}

/// Thrown when bytes are not a `TensorProto` this reader can decode.
class TensorProtoFormatException extends FormatException {
  TensorProtoFormatException(super.message, [super.source, super.offset]);
}

/// A decoded ONNX `TensorProto`.
final class TensorProto {
  TensorProto._({
    required this.dims,
    required this.dataType,
    required this.rawData,
    required this.name,
  });

  /// Decodes a serialized `TensorProto`.
  ///
  /// Throws [TensorProtoFormatException] if the message is truncated, uses an
  /// unknown wire type, or omits `data_type` or `raw_data`.
  factory TensorProto.decode(Uint8List bytes) {
    final reader = _ProtoReader(bytes);
    final dims = <int>[];
    int? dataType;
    Uint8List? rawData;
    var name = '';

    while (!reader.isAtEnd) {
      final (:field, :wireType) = reader.readTag();
      switch ((field, wireType)) {
        case (_dimsField, _WireType.varint):
          dims.add(reader.readVarint());
        case (_dimsField, _WireType.lengthDelimited):
          reader.readPackedVarints(dims);
        case (_dataTypeField, _WireType.varint):
          dataType = reader.readVarint();
        case (_nameField, _WireType.lengthDelimited):
          name = utf8.decode(reader.readBytes());
        case (_rawDataField, _WireType.lengthDelimited):
          rawData = reader.readBytes();
        default:
          reader.skip(wireType);
      }
    }

    if (dataType == null) {
      throw TensorProtoFormatException('missing required field data_type (2)');
    }
    if (rawData == null) {
      throw TensorProtoFormatException(
        'missing raw_data (9); this reader does not decode the typed *_data '
        'fields, and string tensors carry no raw_data at all',
      );
    }
    return TensorProto._(
      dims: List.unmodifiable(dims),
      dataType: OnnxDataType(dataType),
      rawData: rawData,
      name: name,
    );
  }

  static const _dimsField = 1;
  static const _dataTypeField = 2;
  static const _nameField = 8;
  static const _rawDataField = 9;

  /// Empty denotes a scalar.
  final List<int> dims;

  final OnnxDataType dataType;

  /// Tightly packed little-endian elements.
  ///
  /// A view into the enclosing message, so its offset is rarely a multiple of
  /// the element width. Use the typed accessors, not this directly.
  final Uint8List rawData;

  /// Empty when the field is absent.
  final String name;

  /// A scalar has one.
  int get elementCount => dims.fold(1, (a, b) => a * b);

  Float32List asFloat32List() =>
      Float32List.sublistView(_checked(OnnxDataType.float32));

  Float64List asFloat64List() =>
      Float64List.sublistView(_checked(OnnxDataType.float64));

  Int32List asInt32List() =>
      Int32List.sublistView(_checked(OnnxDataType.int32));

  Int64List asInt64List() =>
      Int64List.sublistView(_checked(OnnxDataType.int64));

  Uint8List asUint8List() => _checked(OnnxDataType.uint8);

  /// Returns bytes safe to view as [want], after checking type and length.
  ///
  /// `sublistView` needs the byte offset to divide evenly by the element width.
  /// [rawData] points into the middle of a message and usually does not, so copy
  /// in that case only.
  Uint8List _checked(OnnxDataType want) {
    if (dataType != want) {
      throw StateError(
        "tensor '$name' has element type ${dataType.name}, not ${want.name}",
      );
    }
    final width = want.byteWidth!;
    final expected = elementCount * width;
    if (rawData.length != expected) {
      throw TensorProtoFormatException(
        "tensor '$name' declares dims $dims ($elementCount elements, "
        '$expected bytes) but raw_data holds ${rawData.length} bytes',
      );
    }
    return rawData.offsetInBytes % width == 0
        ? rawData
        : Uint8List.fromList(rawData);
  }

  @override
  String toString() =>
      "TensorProto('$name', ${dataType.name}, dims=$dims, ${rawData.length} bytes)";
}

/// The four protobuf wire types that can appear in a `TensorProto`.
enum _WireType {
  varint(0),
  fixed64(1),
  lengthDelimited(2),
  fixed32(5);

  const _WireType(this.code);
  final int code;

  static _WireType fromCode(int code, int offset) => switch (code) {
        0 => varint,
        1 => fixed64,
        2 => lengthDelimited,
        5 => fixed32,
        _ => throw TensorProtoFormatException(
            'unsupported wire type $code', null, offset),
      };
}

/// A forward-only cursor over a protobuf message.
final class _ProtoReader {
  _ProtoReader(this._bytes);

  final Uint8List _bytes;
  int _offset = 0;

  bool get isAtEnd => _offset >= _bytes.length;

  ({int field, _WireType wireType}) readTag() {
    final tagOffset = _offset;
    final tag = readVarint();
    return (
      field: tag >> 3,
      wireType: _WireType.fromCode(tag & 0x7, tagOffset),
    );
  }

  int readVarint() {
    var result = 0;
    var shift = 0;
    while (true) {
      if (_offset >= _bytes.length) {
        throw TensorProtoFormatException('truncated varint', null, _offset);
      }
      if (shift > 63) {
        throw TensorProtoFormatException(
            'varint wider than 64 bits', null, _offset);
      }
      final byte = _bytes[_offset++];
      result |= (byte & 0x7F) << shift;
      if (byte & 0x80 == 0) return result;
      shift += 7;
    }
  }

  /// Views the next length-delimited field without copying.
  Uint8List readBytes() {
    final lengthOffset = _offset;
    final length = readVarint();
    final end = _offset + length;
    if (length < 0 || end > _bytes.length) {
      throw TensorProtoFormatException(
        'length-delimited field claims $length bytes but only '
        '${_bytes.length - _offset} remain',
        null,
        lengthOffset,
      );
    }
    final view = Uint8List.sublistView(_bytes, _offset, end);
    _offset = end;
    return view;
  }

  /// Appends a packed repeated varint field to [into].
  void readPackedVarints(List<int> into) {
    final packed = _ProtoReader(readBytes());
    while (!packed.isAtEnd) {
      into.add(packed.readVarint());
    }
  }

  void skip(_WireType wireType) {
    switch (wireType) {
      case _WireType.varint:
        readVarint();
      case _WireType.fixed64:
        _advance(8);
      case _WireType.fixed32:
        _advance(4);
      case _WireType.lengthDelimited:
        readBytes();
    }
  }

  void _advance(int count) {
    if (_offset + count > _bytes.length) {
      throw TensorProtoFormatException(
          'truncated fixed-width field', null, _offset);
    }
    _offset += count;
  }
}

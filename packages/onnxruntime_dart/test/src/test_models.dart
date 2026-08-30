/// Locates ONNX models for the test suite.
///
/// Everything comes from the pinned submodule, which carries 876 models and
/// thirteen reference input/output pairs. Nothing is vendored and nothing is
/// downloaded, so models and the runtime that executes them always move
/// together.
library;

import 'dart:io';
import 'dart:typed_data';

import 'paths.dart';

final _testData = fromRoot('third_party/onnxruntime/onnxruntime/test/testdata');

/// Thrown when a model is not present. Callers turn this into a skip.
final class ModelUnavailable implements Exception {
  ModelUnavailable(this.message);

  final String message;

  @override
  String toString() => 'ModelUnavailable: $message';
}

/// A model shipping a reference input and output, in ONNX's standard layout of
/// `model.onnx` beside `test_data_set_N/`.
final class ReferenceModel {
  const ReferenceModel(this.name, this.directory);

  final String name;
  final String directory;

  Uint8List model() => _read('$directory/model.onnx');

  /// Serialized `TensorProto` for input [index] of data set [set].
  Uint8List input(int index, {int set = 0}) =>
      _read('$directory/test_data_set_$set/input_$index.pb');

  /// Serialized `TensorProto` for the expected output [index] of data set [set].
  Uint8List output(int index, {int set = 0}) =>
      _read('$directory/test_data_set_$set/output_$index.pb');

  Uint8List _read(String path) {
    final file = File(path);
    if (file.existsSync()) return file.readAsBytesSync();
    if (!submoduleIsCheckedOut) {
      throw ModelUnavailable(
        'the ONNX Runtime submodule is not checked out, so $name is '
        'unavailable. Run: git submodule update --init third_party/onnxruntime',
      );
    }
    throw ModelUnavailable('$path does not exist');
  }
}

/// Two dense layers ending in a softmax. Shapes [1, 6] to [1, 26].
final voiceCommands = ReferenceModel(
  'test_voice_commands',
  '$_testData/ort_minimal_e2e_test_data/test_voice_commands',
);

/// A bidirectional LSTM, useful for rank-3 shapes. Shapes [5, 1, 2] to [5, 1, 6].
final bidirectionalLstm = ReferenceModel(
  'test_LSTM.tanh.bidirectional',
  '$_testData/CNTK/test_LSTM.tanh.bidirectional',
);

/// ORT's per-element-type identity models, one per ONNX tensor type.
const _nodeTestData = 'js/node/test/testdata';

/// Element types with a dedicated model in the submodule.
const dtypeModels = <String, String>{
  'bool': '$_nodeTestData/test_types_bool.onnx',
  'double': '$_nodeTestData/test_types_double.onnx',
  'float': '$_nodeTestData/test_types_float.onnx',
  'float16': '$_nodeTestData/test_types_float16.onnx',
  'int8': '$_nodeTestData/test_types_int8.onnx',
  'int16': '$_nodeTestData/test_types_int16.onnx',
  'int32': '$_nodeTestData/test_types_int32.onnx',
  'int64': '$_nodeTestData/test_types_int64.onnx',
  'string': '$_nodeTestData/test_types_string.onnx',
  'uint8': '$_nodeTestData/test_types_uint8.onnx',
  'uint16': '$_nodeTestData/test_types_uint16.onnx',
  'uint32': '$_nodeTestData/test_types_uint32.onnx',
  'uint64': '$_nodeTestData/test_types_uint64.onnx',
};

/// Reads a file from anywhere in the submodule, by repository-relative path.
Uint8List readSubmoduleFile(String relativePath) {
  final file = File(fromRoot('third_party/onnxruntime/$relativePath'));
  if (file.existsSync()) return file.readAsBytesSync();
  throw ModelUnavailable(
    submoduleIsCheckedOut
        ? '$relativePath does not exist in the submodule'
        : 'the ONNX Runtime submodule is not checked out. Run: '
            'git submodule update --init third_party/onnxruntime',
  );
}

/// Reads any file from ORT's test corpus by path relative to `testdata`.
Uint8List readOrtTestModel(String relativePath) {
  final file = File('$_testData/$relativePath');
  if (file.existsSync()) return file.readAsBytesSync();
  throw ModelUnavailable(
    submoduleIsCheckedOut
        ? '$_testData/$relativePath does not exist'
        : 'the ONNX Runtime submodule is not checked out. Run: '
            'git submodule update --init third_party/onnxruntime',
  );
}

/// Whether the submodule is available. Tests needing it should skip when false.
bool get submoduleIsCheckedOut => Directory(_testData).existsSync();

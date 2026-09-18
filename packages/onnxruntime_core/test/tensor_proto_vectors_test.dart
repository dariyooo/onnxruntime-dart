@TestOn('vm')
library;

import 'package:test/test.dart';

import 'src/tensor_proto.dart';
import 'src/test_models.dart';

void main() {
  group('TensorProto.decode', () {
    test('decodes a rank-2 input tensor', () {
      final tensor = TensorProto.decode(voiceCommands.input(0));

      expect(tensor.name, 'input_1');
      expect(tensor.dims, [1, 6]);
      expect(tensor.dataType, OnnxDataType.float32);
      expect(tensor.elementCount, 6);
      expect(tensor.rawData, hasLength(6 * 4));

      final values = tensor.asFloat32List();
      expect(values[0], closeTo(6.84655094, 1e-5));
      expect(values[1], closeTo(0.621798158, 1e-5));
      expect(values[5], closeTo(3.96454906, 1e-5));
      expect(values.reduce((a, b) => a + b), closeTo(-17.6923347, 1e-4));
    });

    test('decodes the reference output tensor', () {
      final tensor = TensorProto.decode(voiceCommands.output(0));

      expect(tensor.name, 'dense_1');
      expect(tensor.dims, [1, 26]);
      expect(tensor.elementCount, 26);

      // The model ends in a softmax, so summing to 1.0 checks every one of the
      // 26 values decoded. One bad offset or byte order breaks the sum.
      final values = tensor.asFloat32List();
      expect(values, hasLength(26));
      expect(values.reduce((a, b) => a + b), closeTo(1.0, 1e-6));
    });

    test('decodes rank-3 shapes', () {
      final input = TensorProto.decode(bidirectionalLstm.input(0));
      expect(input.dims, [5, 1, 2]);
      expect(input.elementCount, 10);
      expect(input.asFloat32List()[0], closeTo(0.684251606, 1e-5));

      final output = TensorProto.decode(bidirectionalLstm.output(0));
      expect(output.dims, [5, 1, 6]);
      expect(output.elementCount, 30);
      expect(output.asFloat32List()[2], closeTo(-0.133083895, 1e-5));
    });
  }, skip: submoduleIsCheckedOut ? null : 'ORT submodule not checked out');
}

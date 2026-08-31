/// Where the generator's inputs live, relative to the package root.
library;

const ortHeader =
    '../../third_party/onnxruntime/include/onnxruntime/core/session/'
    'onnxruntime_c_api.h';

const ortBindings = 'lib/src/bindings/ort_bindings.g.dart';

/// On-device training, declared in its own header and compiled only into the
/// `full` build. The generator reads it the same way as the main one: it is
/// another struct of function pointers.
const ortTrainingHeader =
    '../../third_party/onnxruntime/orttraining/orttraining/training_api/'
    'include/onnxruntime_training_c_api.h';

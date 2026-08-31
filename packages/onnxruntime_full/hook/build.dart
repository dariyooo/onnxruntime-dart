// Installs the ONNX Runtime library for the target being built.
//
// The work is in onnxruntime_dart's hook library, shared with the other
// runtime package. All this file decides is which library to install.

import 'package:onnxruntime_hook/onnxruntime_hook.dart';

void main(List<String> args) async => installRuntime(args, OrtVariant.full);

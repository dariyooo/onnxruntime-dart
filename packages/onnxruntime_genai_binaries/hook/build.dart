// Installs the ONNX Runtime GenAI library for the target being built.
//
// The work is in onnxruntime_hook, shared with the runtime and the providers.
// All this file decides is which component to install.

import 'package:onnxruntime_hook/onnxruntime_hook.dart';

void main(List<String> args) async => installGenAi(args);

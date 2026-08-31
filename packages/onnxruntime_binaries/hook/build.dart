// Installs the ONNX Runtime library for the target being built.
//
// One package for both variants rather than one each. They are the same
// library built differently, so exactly one may be installed, and a package
// cannot say "not with that other package": pub has no way to express it.
// Choosing here makes the wrong combination unrepresentable.
//
// The work is in onnxruntime_hook, shared with the provider packages.

import 'package:onnxruntime_hook/onnxruntime_hook.dart';

void main(List<String> args) async => installRuntime(args);

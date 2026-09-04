// Installs the onnxruntime-extensions custom operator library.
//
// The work is in onnxruntime_hook, shared with the runtime and the provider
// packages. All this file names is which component to install.

import 'package:onnxruntime_hook/onnxruntime_hook.dart';

void main(List<String> args) async => installExtensions(args);

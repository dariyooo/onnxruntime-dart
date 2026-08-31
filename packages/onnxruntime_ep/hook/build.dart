// Installs the execution provider libraries the application asked for.
//
// The work is in onnxruntime_dart's hook library, shared with the runtime
// packages. Which providers to install comes from user-defines, so this file
// decides nothing.

import 'package:onnxruntime_hook/onnxruntime_hook.dart';

void main(List<String> args) async => installProviders(args);

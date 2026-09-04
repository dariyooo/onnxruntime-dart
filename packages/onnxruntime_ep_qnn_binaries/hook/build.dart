// Installs the qnn execution provider for the target being built.
//
// The work is in onnxruntime_hook, shared with every other provider and with
// the runtime packages. All this file decides is which provider to install.

import 'package:onnxruntime_hook/onnxruntime_hook.dart';

void main(List<String> args) async => installProvider(args, OrtProvider.qnn);

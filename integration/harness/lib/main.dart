// A window for the integration tests to run in. The tests are the point; this
// shows what the device found so a failing run says something from a glance.

import 'dart:ffi';

import 'package:flutter/material.dart';
import 'package:onnxruntime_dart/native.dart';

void main() => runApp(const HarnessApp());

class HarnessApp extends StatelessWidget {
  const HarnessApp({super.key});

  @override
  Widget build(BuildContext context) {
    late final String summary;
    try {
      summary =
          'ONNX Runtime ${runtimeVersion()}\n'
          'training: ${trainingIsAvailable()}\n'
          'library: ${libraryPathOf(ortApi().ref.GetTrainingApi.cast<Void>()) ?? "unknown"}';
    } on Object catch (e) {
      summary = 'no runtime: $e';
    }
    return MaterialApp(
      home: Scaffold(body: Center(child: Text(summary))),
    );
  }
}

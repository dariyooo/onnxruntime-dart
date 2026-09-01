/// Accelerators on the web.
///
/// Nothing is registered: the providers are compiled into the build being
/// served, so which ones exist is decided by which build that is, and whether
/// the browser exposes the API behind them.
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:onnxruntime_dart/onnxruntime_dart.dart';
import 'package:onnxruntime_dart/src/backend/wasm/loader.dart';
import 'package:onnxruntime_dart/src/backend/wasm/webnn.dart';

import 'accelerator.dart';
import 'runtime.dart';

export 'accelerator.dart';

@JS('navigator')
external JSObject get _navigator;

/// The Asyncify builds are the ones with accelerators, because both of these
/// suspend: requesting a GPU device, and building a WebNN graph.
String? get _skipWithoutAcceleratorBuild =>
    skipWithoutRuntime ??
    (supportsSynchronousCalls
        ? 'this is the plain WebAssembly build, which has no accelerator'
        : null);

List<Accelerator> accelerators() => [
      Accelerator(
        label: 'WebGPU',
        // ONNX Runtime spells it this way and rejects any other spelling.
        name: 'WebGPU',
        ensure: () async {},
        skip: _skipWithoutAcceleratorBuild,
      ),
      Accelerator(
        label: 'WebNN',
        name: 'WEBNN',
        ensure: () async {},
        // Without a device type the EP asks for the default, which a headless
        // browser with no GPU cannot give it. The CPU backend is the one that
        // exists everywhere.
        configuration: const {'deviceType': 'cpu'},
        // Three things have to line up: an Asyncify build, the WebNN glue
        // compiled into it, and a browser that exposes the API. The WebGPU
        // build is Asyncify and has no WebNN, so the build has to be asked
        // rather than inferred from how it suspends.
        skip: _skipWithoutAcceleratorBuild ??
            (!hasWebNn(ortModule)
                ? _webnnNotInBuild
                : (_navigator.has('ml') ? null : _webnnUnavailable)),
      ),
    ];

const _webnnNotInBuild =
    'this build has WebGPU but not WebNN: it was compiled without the '
    'provider, so there is nothing to ask for';

const _webnnUnavailable =
    'this browser does not expose navigator.ml. Chromium has it behind '
    '--enable-features=WebMachineLearningNeuralNetwork';

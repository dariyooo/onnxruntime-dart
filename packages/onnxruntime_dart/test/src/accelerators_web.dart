/// Accelerators on the web.
///
/// Nothing is registered: the providers are compiled into the build being
/// served, so which ones exist is decided by which build that is, and whether
/// the browser exposes the API behind them.
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:onnxruntime_dart/onnxruntime_dart.dart';

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
        skip: _skipWithoutAcceleratorBuild ??
            (_navigator.has('ml') ? _webnnUnexplained : _webnnUnavailable),
      ),
    ];

/// Why WebNN is not exercised even where the browser has it.
///
/// `navigator.ml.createContext()` succeeds directly for cpu, gpu and npu, so
/// the browser is not the limit. ONNX Runtime's own EP still fails at
/// `WebNNExecutionProvider::WebNNExecutionProvider` with "Failed to create
/// WebNN context", which is inside the runtime rather than in this package.
/// Left as a skip with the reason rather than a passing test that proves
/// nothing, or a red one that says nothing new.
const _webnnUnexplained =
    'the browser exposes navigator.ml and creates a context directly, but '
    "ONNX Runtime's WebNN provider fails with 'Failed to create WebNN "
    "context'. Unresolved, and inside the runtime rather than here";

const _webnnUnavailable =
    'this browser does not expose navigator.ml. Chromium has it behind '
    '--enable-features=WebMachineLearningNeuralNetwork';

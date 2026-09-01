/// Making WebGPU usable on the web.
///
/// Nothing to register: the provider is compiled into the build being served,
/// so all that decides it is which build that is. The Asyncify builds are the
/// ones that have it, because requesting a device suspends.
library;

import 'package:onnxruntime_dart/onnxruntime_dart.dart';

import 'runtime.dart';

/// What a session calls the provider. ONNX Runtime spells the web one in
/// caps, and rejects any other spelling by name.
const webGpuProviderName = 'WebGPU';

/// Reason to skip, or null when WebGPU can be used here.
String? get skipWithoutWebGpu =>
    skipWithoutRuntime ??
    (supportsSynchronousCalls
        ? 'this is the plain WebAssembly build, which has no WebGPU'
        : null);

/// Nothing to do: the provider is linked in.
Future<void> ensureWebGpu() async {}

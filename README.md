# onnx-runtime-dart

Comprehensive bindings to the ONNX Runtime C API from standalone Dart, with the
binaries to go with them. No Flutter dependency: everything here works in a
plain Dart program, and works the same in a Flutter one.

[`examples/gallery`](examples/gallery) runs six models through the
packages.

## The packages

| Package | What it is |
| --- | --- |
| [`onnxruntime_dart`](packages/onnxruntime_dart) | The bindings and the API of the base runtime. |
| [`onnxruntime_binaries`](packages/onnxruntime_binaries) | The native binaries of `onnxruntime_dart` bundled as native assets. |
| [`onnxruntime_extensions`](packages/onnxruntime_extensions) | Tokenizers, text, image and audio operators that run inside the graph. |
| [`onnxruntime_extensions_binaries`](packages/onnxruntime_extensions_binaries) | The native binaries of `onnxruntime_extensions`. |
| [`onnxruntime_genai`](packages/onnxruntime_genai) | Token generation, KV caching and sampling on top of a `onnxruntime_dart` session. |
| [`onnxruntime_genai_binaries`](packages/onnxruntime_genai_binaries) | The native binaries of `onnxruntime_genai`. |
| [`onnxruntime_hook`](packages/onnxruntime_hook) | The build hook the other packages use. |

### Execution providers

Each ships separately from the runtime and uses the upstream ONNX version.

Every one of these is two packages: the Dart API, and the compiled native
binary it registers.

| Package | Hardware |
| --- | --- |
| [`onnxruntime_ep_webgpu`](packages/onnxruntime_ep_webgpu) | GPUs, through Vulkan, D3D12 or Metal. |
| [`onnxruntime_ep_webgpu_binaries`](packages/onnxruntime_ep_webgpu_binaries) | The plugin that API registers. |
| [`onnxruntime_ep_cuda`](packages/onnxruntime_ep_cuda) | NVIDIA GPUs. Needs the CUDA runtime on the machine. |
| [`onnxruntime_ep_cuda_binaries`](packages/onnxruntime_ep_cuda_binaries) | The plugin that API registers. |
| [`onnxruntime_ep_qnn`](packages/onnxruntime_ep_qnn) | Qualcomm NPUs, carrying the AI Runtime it loads. |
| [`onnxruntime_ep_qnn_binaries`](packages/onnxruntime_ep_qnn_binaries) | The plugin that API registers. |

### The web

The WebAssembly runtime is bundled as a flutter asset or you can fetch it on your own at runtime.
Currently, there is no way to load dynamic libraries on web and therefore, the precompiled binaries of this package include the EPs.

| Package | Accelerators |
| --- | --- |
| [`onnxruntime_web`](packages/onnxruntime_web) | XNNPACK. The smallest. |
| [`onnxruntime_web_webgpu`](packages/onnxruntime_web_webgpu) | XNNPACK and WebGPU. |
| [`onnxruntime_web_webgpu_webnn`](packages/onnxruntime_web_webgpu_webnn) | XNNPACK, WebGPU and WebNN. |

## Working on this repository

How CI builds and tests the binaries, and how a release is cut, is in
[Building, testing and releasing](doc/building-and-releasing.md).

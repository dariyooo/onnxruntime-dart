# onnx-runtime-dart

Comprehensive bindings to the ONNX Runtime C API from standalone Dart, with the
binaries to go with them. No Flutter dependency: everything here works in a
plain Dart program, and works the same in a Flutter one.

Start with [`onnxruntime_dart`](packages/onnxruntime_dart) — its README is the
documentation. The rest of these exist so it has something to run against.

## The packages

| Package | Version | What it is |
| --- | --- | --- |
| [`onnxruntime_dart`](packages/onnxruntime_dart) | 0.1.0 | The bindings and the API. The only one most applications name. |
| [`onnxruntime_binaries`](packages/onnxruntime_binaries) | 1.29.0 | The native runtime for desktop and mobile, installed as a code asset. |
| [`onnxruntime_extensions`](packages/onnxruntime_extensions) | 0.15.0 | Tokenizers, text, image and audio operators that run inside the graph. |
| [`onnxruntime_hook`](packages/onnxruntime_hook) | 1.29.0 | The build hook the others install through. Not named directly. |

### Execution providers

Each ships separately from the runtime and is versioned by ONNX Runtime rather
than by us. Add one to reach the hardware it names.

| Package | Version | Hardware |
| --- | --- | --- |
| [`onnxruntime_ep_webgpu`](packages/onnxruntime_ep_webgpu) | 0.3.0 | GPUs, through Vulkan, D3D12 or Metal. |
| [`onnxruntime_ep_cuda`](packages/onnxruntime_ep_cuda) | 0.1.0 | NVIDIA GPUs. Needs the CUDA runtime on the machine. |
| [`onnxruntime_ep_qnn`](packages/onnxruntime_ep_qnn) | 2.5.0 | Qualcomm NPUs, carrying the AI Runtime it loads. |

### The web

The WebAssembly runtime is fetched at startup rather than linked in, so which
build you serve decides which accelerators exist. Pick one.

| Package | Version | Accelerators |
| --- | --- | --- |
| [`onnxruntime_web`](packages/onnxruntime_web) | 1.29.0 | XNNPACK. The smallest. |
| [`onnxruntime_web_webgpu`](packages/onnxruntime_web_webgpu) | 1.29.0 | XNNPACK and WebGPU. |
| [`onnxruntime_web_webgpu_webnn`](packages/onnxruntime_web_webgpu_webnn) | 1.29.0 | XNNPACK, WebGPU and WebNN. |

## Building and testing

One workflow, with one switch. By default it builds every binary and tests what
it built — no binary is published without something loading it first. Give the
`from_release` input a runtime tag, or `latest`, and it skips the builds and
runs the same tests against what is already published instead. That is also
what the weekly run does, so a release that stops installing is noticed without
waiting for a push.

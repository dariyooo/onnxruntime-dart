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

The WebAssembly runtime is fetched at startup rather than linked in, so which
build you serve decides which accelerators exist. Pick one.

| Package | Accelerators |
| --- | --- |
| [`onnxruntime_web`](packages/onnxruntime_web) | XNNPACK. The smallest. |
| [`onnxruntime_web_webgpu`](packages/onnxruntime_web_webgpu) | XNNPACK and WebGPU. |
| [`onnxruntime_web_webgpu_webnn`](packages/onnxruntime_web_webgpu_webnn) | XNNPACK, WebGPU and WebNN. |

## Building and testing

One workflow, with one switch. By default it builds every binary and tests what
it built, so no binary is published without something loading it first. Give the
`from_release` input a runtime tag, or `latest`, and it skips the builds and
runs the same tests against what is already published instead. That is also
what the weekly run does, so a release that stops installing is noticed without
waiting for a push.

Releasing is tagging, one component at a time. The tag names what it releases,
and the pipeline runs that component alone:

| tag | releases |
| --- | --- |
| `runtime-v*` | the runtime, base and full |
| `ep-webgpu-v*` | the WebGPU provider |
| `ep-cuda-v*` | the CUDA provider |
| `ep-qnn-v*` | the QNN provider |
| `extensions-v*` | the operator library |
| `genai-v*` | the GenAI library |

The version in the tag is the package's own, so `runtime-v1.29.0` releases
`onnxruntime_binaries` at `1.29.0`.

So a provider that gains a version is released by its own tag and nothing else
is rebuilt. Pushing to a branch never publishes, whichever branch it is.

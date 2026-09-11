# onnxruntime_dart

Run ONNX models from Dart and Flutter. Android, iOS, macOS, Linux, Windows and
the web, from one codebase.

Bindings to [ONNX Runtime](https://onnxruntime.ai), generated from pinned
headers rather than written by hand, so the whole C API is reachable and none of
it can drift from the version it was built against.

## Platforms

| Platform | Architectures | Compiled-in providers |
| --- | --- | --- |
| Android | arm64-v8a, armeabi-v7a, x86_64, x86 | CPU, XNNPACK |
| iOS | device arm64, simulator arm64 and x86_64 | CPU, XNNPACK, CoreML |
| macOS | arm64, x86_64 | CPU, XNNPACK, CoreML |
| Linux | x86_64, arm64 | CPU, XNNPACK |
| Windows | x86_64, arm64 | CPU, XNNPACK |
| Web | wasm32 | CPU, XNNPACK; WebGPU and WebNN per build |

Every library is built from the pinned submodule with every operator and every
opset. Nothing is trimmed to save size.

On the web the accelerators are compiled in rather than loaded, so which of the
three builds you serve decides what you get. Everywhere else they are packages
you add.

## Contents

- [Quick start](#quick-start): install and run your first model
- [Tensors and shapes](#tensors-and-shapes)
- [Choosing a runtime](#choosing-a-runtime): `base` or `full`
- [Execution providers](#execution-providers): GPUs and NPUs
- [Extra operators](#extra-operators): tokenizers, images, audio
- [The web](#the-web)
- [Keeping inference off the calling thread](#keeping-inference-off-the-calling-thread)
- [On-device training](#on-device-training)
- [The packages](#the-packages): how the pieces fit together
- [Going further](#going-further): the full C API, your own providers

## Quick start

Two packages: the bindings, and the engine.

```sh
dart pub add onnxruntime_dart onnxruntime_binaries
```

They are separate so you can pin the engine independently, bring your own build,
or ship none at all. Without one, calls throw `OrtRuntimeMissing` with
instructions rather than failing to load.

```dart
import 'dart:io';
import 'dart:typed_data';
import 'package:onnxruntime_dart/onnxruntime_dart.dart';

void main() async {
  // Readies the runtime. On native the library is already loaded and this
  // does nothing, ignoring the url. On the web it downloads and starts the
  // WebAssembly module from that url, which is why this is a Future.
  //
  // onnxruntime_web publishes the url; see "the web".
  await openOnnxRuntime(web: WebRuntimeOptions('url/to/ort-wasm.mjs'));

  final session = Session.fromBytes(File('mnist.onnx').readAsBytesSync());

  // A model tells you what it wants.
  for (final input in session.inputs) {
    print(input); // Input3 float32 [1, 1, 28, 28]
  }

  final pixels = Float32List(1 * 1 * 28 * 28);
  final input =
      OrtTensor.fromData(OrtElementType.float32, pixels, [1, 1, 28, 28]);
  final outputs = session.run({'Input3': input});

  print(outputs['Plus214_Output_0']!.view.float32s);

  // Free what you made, in the order you made it. Sessions and tensors hold
  // memory the garbage collector cannot see, so this is the one rule you have
  // to follow. Forgetting leaks; it cannot corrupt anything, because using or
  // releasing something twice throws.
  input.release();
  for (final output in outputs.values) {
    output.release();
  }
  session.release();
}
```

## Tensors and shapes

A tensor is a flat list plus a shape. `[1, 1, 28, 28]` means one image, one
channel, 28 by 28: 784 floats in row-major order.

A `-1` in a model's shape is a dimension it decides at run time, usually batch
size. `session.inputs.first.isDynamic` tells you whether any dimension is.

## Choosing a runtime

`base` is the default and is what almost every application wants. `full` adds
only what cannot be loaded at run time and has to be compiled in.

| | base | full |
| --- | --- | --- |
| All operators and opsets | yes | yes |
| Contrib and ML operators | yes | yes |
| LoRA adapters | yes | yes |
| Loading provider libraries | yes | yes |
| On-device training APIs | **no** | **yes** |

Training is the whole difference. It sits behind `ENABLE_TRAINING_APIS` at
compile time and covers checkpoints, train, eval and optimizer steps,
learning-rate schedules, parameter access, and exporting an inference model.

```yaml
hooks:
  user_defines:
    onnxruntime_binaries:
      variant: full
```

`trainingIsAvailable()` reports which one you have, so a `base` build fails a
check rather than crashing.

### Bringing your own build

```yaml
hooks:
  user_defines:
    onnxruntime_binaries:
      local_build: path/to/lib
```

## Execution providers

CPU always works and XNNPACK is compiled in everywhere, so most models need
nothing here. Anything else is a separate package, because a GPU backend is tens
to hundreds of megabytes and most applications want none of them.

Each is a package named `onnxruntime_ep_<provider>`. What is compiled into
every build is in [Platforms](#platforms) and needs nothing.

| Provider | Android | iOS | macOS | Linux | Windows | Web |
| --- | --- | --- | --- | --- | --- | --- |
| WebGPU | 64-bit ABIs | yes | yes | yes | yes | compiled in |
| CUDA | no | no | no | x64, arm64 | x64, arm64 | no |
| QNN | no | no | no | x64, arm64 | x64, arm64 | no |

Two packages: the API, and the plugin it registers. They are separate so that
an application can move one without the other, or take the API alone and supply
its own build at run time.

```sh
dart pub add onnxruntime_ep_webgpu onnxruntime_ep_webgpu_binaries
```

```dart
import 'package:onnxruntime_ep_webgpu/onnxruntime_ep_webgpu.dart';

registerWebGpu();
```

Each package finds its own library and registers it, returning whether it was
there.

Register before the sessions that should use it, not before all of them. A
provider registered now is available to every session created afterwards, so
one downloaded at run time works exactly the same way; sessions already built
keep what they were built with. Do not register from one isolate while another
is creating a session, though, because it mutates the environment.

Unregistering is the one with a hard rule: release every session using a
provider before unloading its library.

Notes on the table:

- **WebGPU** reaches Vulkan on Android and Linux, D3D12 or Vulkan on Windows,
  and Metal on Apple. Only the 64-bit Android ABIs, where Vulkan is dependable.
- **On Windows the WebGPU provider needs a shader compiler beside it.** This
  provider is built against Dawn's D3D12 backend, which compiles shaders
  through `dxcompiler.dll` and `dxil.dll`. Windows ships neither, and the
  provider loads them by name at the first compile rather than at load time, so
  a missing one looks like a working plugin that fails on its first run. Ship
  both next to `onnxruntime_providers_webgpu.dll`, from the upstream DirectX
  Shader Compiler release.
- **On Windows ARM take that compiler from the Windows SDK**, not from the DXC
  release. Every current DXC distribution, the GitHub release and the
  `Microsoft.Direct3D.DXC` NuGet package alike, puts ARM64EC under `bin/arm64`
  rather than ARM64: the PE header says AMD64, the load config carries a CHPE
  pointer, and there is no ARM64X relocation table, so a native ARM64 process
  refuses it and `LoadLibrary` fails with error 87. The SDK ships a real ARM64
  build under `bin/<version>/arm64`. Take a recent one: 10.0.26100.0 carries
  DXC 1.8 and works, while 10.0.22621.0 carries 1.6, which Dawn loads and then
  dies on with no message at all.
- **CUDA** ships against two toolkits and defaults to 12, which asks less of the
  driver. `build: cuda13` selects the other, and on arm64 it is the only one.
- **CUDA on Windows ARM needs the 13.4 developer preview.** That target is
  newer than the stable redistributables, which carry `libcublas` and
  `cuda_cudart` for `linux-sbsa`, `linux-x86_64` and `windows-x86_64` only. The
  toolkit for it lives under `packages.nvidia.com/prerelease/cuda/13.4.0`, and
  the provider wants `cublas64_13.dll` and `cublasLt64_13.dll` from it beside
  the plugin, as on x64. Take them from the `arm64` directories rather than the
  `_cross_x86_64` ones, which carry the same file names for x64 and fail to
  load with error 193. CI loads the plugin against this, so it is tested, but
  it is preview software and worth treating as such.
- **QNN** carries the Qualcomm AI Runtime with it. Not Android: there QNN is
  linked into a whole runtime rather than published as a loadable plugin.
- **On the web** nothing is loaded: WebGPU and WebNN are compiled into two of
  the three builds, so serving one is how you choose. CUDA and QNN have no web
  equivalent at all.

## Extra operators

Models often need tokenizers, image decoding or audio preprocessing, which core
ONNX has no operators for.
[onnxruntime-extensions](https://github.com/microsoft/onnxruntime-extensions)
provides them and runs them inside the graph, so you do not reimplement BPE or a
mel spectrogram in Dart.

Two packages, as with the providers: the API, and the operator library it
loads.

```sh
dart pub add onnxruntime_extensions onnxruntime_extensions_binaries
```

```dart
import 'package:onnxruntime_extensions/onnxruntime_extensions.dart';

final path = extensionsPath();
final session = Session.fromBytes(
  bytes,
  options: SessionOptions(customOpsLibraries: [if (path != null) path]),
);
```

Every native platform. Not the web, where operators have to be compiled into the
runtime rather than loaded beside it.

## The web

The same code runs in a browser, with two differences worth knowing up front.

The runtime is a WebAssembly module that has to be downloaded, so you tell
`openOnnxRuntime` where it is. And there are three builds, differing in which
accelerators are compiled in; the one you serve decides whether you can use the
synchronous API.

```sh
dart pub add onnxruntime_web
```

```dart
import 'package:onnxruntime_web/onnxruntime_web.dart' as ort_assets;

await openOnnxRuntime(web: WebRuntimeOptions(ort_assets.ortLoaderUrl));
```

That, plus `Session.load` and `runAsync`, works on every build and every
platform. If that is all you need, you are done.

For the WebGPU and WebNN builds, picking a build at run time, and the things
that genuinely cannot work in a browser, see
[Running on the web](doc/web.md).


## Keeping inference off the calling thread

`runAsync` keeps a run off the *calling* thread only where something else can
carry it. On native that is ONNX Runtime's own intra-op pool, so the isolate
stays free. On the web there is no such pool to hand a whole run to: the plain
build runs it on whichever thread called it, and the Asyncify builds suspend
while the GPU works but still do their CPU work there. A long model on the page
freezes the page.

The fix is the same on both platforms, and the package deliberately does not
ship it: **a session belongs to the thread that created it.** There is no pool
and no sendable session, because how many threads you want, and how long they
live, is an application's decision rather than a binding's. What the package
owes is that a session works when you create one somewhere else, which is what
`test/isolate_test.dart` and `test/worker_test.dart` check.

| | Native | Web |
| --- | --- | --- |
| The thread | an isolate | a worker |
| Sending the model | the bytes, over a port | the bytes, by `postMessage` |
| Sending a session | never, it is not sendable | never, it is not sendable |
| Sending a result | copied out, the view borrows memory | copied out, the view borrows heap |
| Worked example | [`example/isolates.dart`](example/isolates.dart) | [`example/workers.dart`](example/workers.dart) |

Both examples show the same two shapes, because the choice is the same one on
either platform. A thread per call is simple and pays to load the model every
time. A thread that loads once and answers many requests is what production
looks like.

The web has one wrinkle native does not: a worker runs a script, not a closure,
so its body is a program of its own that you compile beside your page.

```sh
dart compile js example/worker_body.dart -o web/worker_body.dart.js
```

The page fetches the runtime once and hands the worker the bytes, because a
worker resolves a relative URL against its own script rather than the page.
Inside the worker, use `Session.load` and `runAsync`: that way the same worker
body serves the plain build and the WebGPU one.

## On-device training

In the `full` variant only.

```dart
import 'package:onnxruntime_dart/native.dart';

if (trainingIsAvailable()) {
  final api = trainingApi();
}
```

Calling it on a `base` build throws `OrtTrainingUnavailable` rather than
crashing, because `GetTrainingApi` returns null there and that is detectable.

## The packages

Small packages that compose, so an application ships only what it uses.

Downloads are per target, compressed, from the published releases.

| Package | What it is | Download |
| --- | --- | --- |
| `onnxruntime_dart` | Bindings and the API. No binaries. | Dart only |
| `onnxruntime_binaries` | The engine, one variant per build | up to 12 MB |
| `onnxruntime_ep_webgpu_binaries` | WebGPU provider | tens of MB |
| `onnxruntime_ep_cuda_binaries` | CUDA provider | 70 to 333 MB |
| `onnxruntime_ep_qnn_binaries` | QNN provider and the Qualcomm runtime | 55 to 89 MB |
| `onnxruntime_extensions_binaries` | Tokenizers, image and audio operators | about 1 MB |
| `onnxruntime_genai_binaries` | Token generation on top of a session | 3 to 24 MB |
| `onnxruntime_web*` | The WebAssembly builds, as Flutter assets | 4 to 10 MB |

Each is built and released on its own pipeline, so a provider that will not
compile cannot stop the runtime from being built. Every archive is verified
against the SHA-256 published beside it before it is installed.

`onnxruntime_dart` depends on none of the others and names none of them. That is
deliberate: providers depend on it, never the other way round, which is what
makes the next section possible.

## Going further

Two things most applications never need:

- [Adding an execution provider we do not package](doc/extending.md#adding-a-provider-we-do-not-package),
  if you have a provider library of your own.
- [Reaching the complete C API](doc/extending.md#the-complete-c-api), for the
  parts of ONNX Runtime the ordinary Dart API does not cover.

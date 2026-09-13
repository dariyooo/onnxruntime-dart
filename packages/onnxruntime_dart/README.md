# onnxruntime_dart

Run ONNX models from Dart and Flutter. Android, iOS, macOS, Linux, Windows and
the web, from one codebase.

Bindings to [ONNX Runtime](https://onnxruntime.ai). They are generated from the
pinned C headers instead of written by hand, so the whole C API is available and
always matches the version the binaries were built from.

## Platforms

| Platform | Architectures | Compiled-in providers |
| --- | --- | --- |
| Android | arm64-v8a, armeabi-v7a, x86_64, x86 | CPU, XNNPACK |
| iOS | device arm64, simulator arm64 and x86_64 | CPU, XNNPACK, CoreML |
| macOS | arm64, x86_64 | CPU, XNNPACK, CoreML |
| Linux | x86_64, arm64 | CPU, XNNPACK |
| Windows | x86_64, arm64 | CPU, XNNPACK |
| Web | wasm32 | CPU, XNNPACK; WebGPU and WebNN per build |

Every library is built from the pinned submodule with all operators and all
opsets included. Nothing is removed to save size.

On the web, accelerators are compiled into the runtime instead of loaded at
startup, so the build you serve decides which ones you get. On every other
platform you add them as packages.

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

You need two packages: the bindings and the runtime.

```sh
dart pub add onnxruntime_dart onnxruntime_binaries
```

They are separate so you can pin the runtime version yourself, supply your own
build, or ship no binaries at all. If no runtime is present, calls throw
`OrtRuntimeMissing` with instructions instead of failing to load.

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

A `-1` in a model's shape means the model chooses that dimension at run time.
It is usually the batch size. `session.inputs.first.isDynamic` tells you whether
a dimension is dynamic.

## Choosing a runtime

`base` is the default and is what almost every application needs. `full` adds
the features that have to be compiled in because they cannot be loaded later.

| | base | full |
| --- | --- | --- |
| All operators and opsets | yes | yes |
| Contrib and ML operators | yes | yes |
| LoRA adapters | yes | yes |
| Loading provider libraries | yes | yes |
| On-device training APIs | **no** | **yes** |

Training is the only difference. It is behind the `ENABLE_TRAINING_APIS`
compile flag and covers checkpoints, train, eval and optimizer steps,
learning-rate schedules, parameter access, and exporting an inference model.

```yaml
hooks:
  user_defines:
    onnxruntime_binaries:
      variant: full
```

Call `trainingIsAvailable()` to check which build you have. On a `base` build
it returns false, so you get a failed check instead of a crash.

### Bringing your own build

```yaml
hooks:
  user_defines:
    onnxruntime_binaries:
      local_build: path/to/lib
```

## Execution providers

CPU always works, and XNNPACK is compiled into every build, so most models need
nothing from this section. Other providers are separate packages, because a GPU
backend is tens to hundreds of megabytes and most applications do not need one.

Each provider is a package named `onnxruntime_ep_<provider>`. The providers
already compiled into every build are listed under [Platforms](#platforms) and
need no package.

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

Each package locates its own library and registers it. The call returns whether
the library was found.

Register a provider before you create the sessions that should use it. Any
session created after the call can use it, and sessions created before it keep
what they had. This means a provider downloaded at run time works the same way
as one bundled with the app.

One restriction: do not register a provider in one isolate while another isolate
is creating a session. Registering changes shared state.

Unregistering has one rule you must follow. Release every session that uses a
provider before you unload its library.

Some providers need extra files or a particular driver on the target
platform. Those requirements are in
[Execution provider notes](doc/providers.md). The short version: WebGPU on
Windows needs a shader compiler shipped beside it, and CUDA needs a matching
toolkit on the machine.

## Extra operators

Many models need tokenizers, image decoding or audio preprocessing. Core ONNX
has no operators for these.
[onnxruntime-extensions](https://github.com/microsoft/onnxruntime-extensions)
adds them and runs them inside the graph, so you do not have to reimplement BPE
or a mel spectrogram in Dart.

Two packages, like the providers: the API and the operator library it loads.

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

This works on every native platform. It does not work on the web, where
operators have to be compiled into the runtime instead of loaded next to it.

## The web

The same code runs in a browser. Two things are different.

The runtime is a WebAssembly module that has to be downloaded, so you tell
`openOnnxRuntime` where to find it. And there are three builds, each with
different accelerators compiled in. The build you serve decides whether you can
use the synchronous API.

```sh
dart pub add onnxruntime_web
```

```dart
import 'package:onnxruntime_web/onnxruntime_web.dart' as ort_assets;

await openOnnxRuntime(web: WebRuntimeOptions(ort_assets.ortLoaderUrl));
```

That, together with `Session.load` and `runAsync`, works on every build and
every platform. If that is all you need, you are done.

For the WebGPU and WebNN builds, choosing a build at run time, and what cannot
work in a browser, see [Running on the web](doc/web.md).


## Keeping inference off the calling thread

`runAsync` only moves work off the calling thread if something else can take
it. On native, ONNX Runtime has its own thread pool, so the isolate stays free.

On the web there is no pool to hand a whole run to. The plain build runs the
model on whatever thread called it. The Asyncify builds pause while the GPU
works, but still do their CPU work on the calling thread. Either way, a slow
model on the main thread freezes the page.

The solution is the same on both platforms: run the model on another thread.
**A session belongs to the thread that created it.** You cannot send a session
between threads, and this package does not provide a thread pool, because how
many threads you want and how long they live is your application's decision.

What this package guarantees is that a session works when you create it on
another thread. `test/isolate_test.dart` and `test/worker_test.dart` check
this.

| | Native | Web |
| --- | --- | --- |
| The thread | an isolate | a worker |
| Sending the model | the bytes, over a port | the bytes, by `postMessage` |
| Sending a session | never, it is not sendable | never, it is not sendable |
| Sending a result | copied out, the view borrows memory | copied out, the view borrows heap |
| Worked example | [`example/isolates.dart`](example/isolates.dart) | [`example/workers.dart`](example/workers.dart) |

Both examples show the same two approaches, because the choice is the same on
either platform. One thread per call is simpler, but reloads the model every
time. One thread that loads the model once and answers many requests is what
most applications want.

The web has one extra step. A worker runs a script rather than a closure, so
the worker body is a separate program that you compile alongside your page.

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

The packages are kept small and separate so your application ships only what it
uses. Each download is compressed and specific to the platform you build for.

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

Each package is built and released by its own pipeline, so a provider that
fails to compile does not stop the runtime from being built. Every archive is
checked against the SHA-256 published next to it before it is installed.

`onnxruntime_dart` does not depend on any of the other packages and does not
name them. This is deliberate. Providers depend on it, never the other way
round, which is what lets you package a provider we do not ship.

## Going further

Two things most applications do not need:

- [Adding an execution provider we do not package](doc/extending.md#adding-a-provider-we-do-not-package),
  if you have a provider library of your own.
- [Reaching the complete C API](doc/extending.md#the-complete-c-api), for the
  parts of ONNX Runtime the ordinary Dart API does not cover.

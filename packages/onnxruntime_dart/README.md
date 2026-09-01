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

- [Quick start](#quick-start) — install and run your first model
- [Tensors and shapes](#tensors-and-shapes)
- [Choosing a runtime](#choosing-a-runtime) — `base` or `full`
- [Execution providers](#execution-providers) — GPUs and NPUs
- [Extra operators](#extra-operators) — tokenizers, images, audio
- [The web](#the-web)
- [On-device training](#on-device-training)
- [The packages](#the-packages) — how the pieces fit together
- [Going further](#going-further) — the full C API, your own providers

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
| CUDA | — | — | — | x64, arm64 | x64, arm64 | — |
| QNN | — | — | — | x64, arm64 | x64, arm64 | — |

```sh
dart pub add onnxruntime_ep_webgpu
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
- **CUDA** ships against two toolkits and defaults to 12, which asks less of the
  driver. `build: cuda13` selects the other, and on arm64 it is the only one.
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

```sh
dart pub add onnxruntime_extensions
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

The API is the same. The one difference is that the runtime has to be fetched,
which cannot happen synchronously, so `openOnnxRuntime` needs to know where it
is.

```sh
dart pub add onnxruntime_web
```

```dart
import 'package:onnxruntime_web/onnxruntime_web.dart' as ort_assets;

await openOnnxRuntime(web: WebRuntimeOptions(ort_assets.ortLoaderUrl));
```

One url, because the runtime looks for its `.wasm` next to the `.mjs` and the
asset packages ship them together. Pass `wasm:` as well if a bundler has moved
them apart, or `wasmBytes:` if you already have it in memory.

Three builds, and you pick one by which package you depend on:

| Package | Accelerators | Works today |
| --- | --- | --- |
| `onnxruntime_web` | XNNPACK | yes |
| `onnxruntime_web_webgpu` | XNNPACK, WebGPU | not yet |
| `onnxruntime_web_webgpu_webnn` | XNNPACK, WebGPU, WebNN | not yet |

The accelerator builds are compiled with Asyncify, because WebGPU needs an
asynchronous path to read results back off the GPU. That changes the calling
convention rather than just the speed: `OrtRun` returns a promise instead of a
handle. This backend is synchronous, so it refuses those builds by name rather
than misreading a promise as a result.

Some things cannot work there and say so rather than failing quietly:

- **No `dlopen`**, so providers and custom operators have to be compiled into
  the build you serve rather than added as packages.
- **No filesystem**, so profiling and optimized-model output have nowhere to go.
- **One thread.** More needs `SharedArrayBuffer`, which needs the page served
  cross-origin isolated with COOP and COEP. That is the page's choice, so the
  default is the one that works everywhere.
- **No `runAsync`.** The synchronous build exports no asynchronous run, and a
  browser has no isolates, so a long model blocks the page. Splitting the work
  across frames or a web worker is the answer until the Asyncify path lands.

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

| Package | What it is | Size |
| --- | --- | --- |
| `onnxruntime_dart` | Bindings and the API. No binaries. | small |
| `onnxruntime_binaries` | The engine, one variant per build | tens of MB |
| `onnxruntime_ep_webgpu` | WebGPU provider | tens of MB |
| `onnxruntime_ep_cuda` | CUDA provider | hundreds of MB |
| `onnxruntime_ep_qnn` | QNN provider and the Qualcomm runtime | hundreds of MB |
| `onnxruntime_extensions` | Tokenizers, image and audio operators | ~3 MB |
| `onnxruntime_web*` | The WebAssembly builds, as Flutter assets | tens of MB |

Each is built and released on its own pipeline, so a provider that will not
compile cannot stop the runtime from being built. Every archive is verified
against the SHA-256 published beside it before it is installed.

`onnxruntime_dart` depends on none of the others and names none of them. That is
deliberate: providers depend on it, never the other way round, which is what
makes the next section possible.

## Going further

### Adding a provider we do not package

A provider is a shared library exporting `CreateEpFactories`, and nothing about
the ones here is privileged. If you have one we do not ship, package it the same
way.

The only constraint is that `@Native` needs a compile-time constant asset id, so
it can only be written in the package that owns the asset. That is why providers
are packages rather than entries in a table here.

```dart
import 'dart:ffi';
import 'package:onnxruntime_dart/native.dart';

@Native<Void Function()>(
  symbol: 'CreateEpFactories',
  assetId: 'package:my_provider/provider',
)
external void _entryPoint();

bool registerMine() {
  final path = loadedLibraryPath(
    () => Native.addressOf<NativeFunction<Void Function()>>(_entryPoint).cast(),
    // Checked against the file the loader names. Every provider exports the
    // same symbol, so without this an asset you did not install resolves to
    // whichever library did, and the runtime is handed the wrong file.
    stem: 'onnxruntime_providers_mine',
  );
  if (path == null) return false;

  final environment = OrtEnvironment.instance();
  registerExecutionProviderLibrary(
    environment.api,
    environment.handle,
    name: 'mine',
    path: path,
  );
  return true;
}
```

Your package needs a build hook that installs the library as a code asset named
`provider`. `onnxruntime_hook` does that work, and `onnxruntime_ep_webgpu` is
thirty lines and is the whole example.

Already have the library on disk? `registerProviderLibrary(name:, path:)` takes
any path, no package required.

The same shape works for a custom operator library: export `RegisterCustomOps`
instead and pass the path to `SessionOptions(customOpsLibraries: [...])`.

### The complete C API

`onnxruntime_dart.dart` is the ergonomic surface and covers the common path. It
is not the ceiling.

```dart
import 'package:onnxruntime_dart/native.dart';
```

Every function in every API struct is generated from the pinned headers, so
completeness is a property of the build rather than a goal. Each has a wrapper
taking and returning Dart values, allocating what the call needs and turning a
failed `OrtStatus` into an `OrtException`. The raw function pointer is still
there when a wrapper cannot express what you need, such as a callback.

`native.dart` also holds what needs the loader rather than the runtime, which is
why provider registration lives there: the shared library has to compile for the
web, and that means no `dart:ffi` above the backend seam.

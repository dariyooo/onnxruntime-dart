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
- [Keeping inference off the calling thread](#keeping-inference-off-the-calling-thread)
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

Two differences. The runtime has to be fetched, which cannot happen
synchronously, so `openOnnxRuntime` needs to know where it is. And which of the
three builds you serve decides whether you call the synchronous API or the
asynchronous one, because ONNX Runtime compiles the accelerator builds
differently.

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

| Package | Accelerators | How you call it |
| --- | --- | --- |
| `onnxruntime_web` | XNNPACK | either form |
| `onnxruntime_web_webgpu` | XNNPACK, WebGPU | `Session.load` and `runAsync` |
| `onnxruntime_web_webgpu_webnn` | XNNPACK, WebGPU, WebNN | `Session.load` and `runAsync` |

The accelerator builds are compiled with Asyncify, because WebGPU needs an
asynchronous path to read results back off the GPU. That changes the calling
convention rather than the speed: creating a session and running it can suspend
and hand back a promise. The right backend is chosen from the build itself, and
the synchronous forms refuse there rather than mistaking a promise for a result.

`Session.load` exists for this and works everywhere, completing immediately on
every other platform, so code that has to run on all three builds uses it.

### Choosing a build at run time

The build is not a compile-time decision. `openOnnxRuntime` takes a url, so a
page can look at the browser it is in and fetch accordingly:

```dart
final gpu = web.window.navigator.has('gpu');
await openOnnxRuntime(
  web: WebRuntimeOptions(gpu ? webgpuLoaderUrl : plainLoaderUrl),
);
```

Serve the files yourself rather than depending on all three asset packages,
which would bundle every build into the app.

The accelerators cannot be loaded separately, and that is upstream rather than
here: ONNX Runtime links WebNN and WebGPU into the wasm and injects their
JavaScript glue at link time, so there is no library to load even if the build
allowed it.

Some things cannot work there and say so rather than failing quietly:

- **WebNN needs a little JavaScript, and this package supplies it.** WebGPU's
  implementation is inside the WebAssembly module, so naming it is enough.
  WebNN's is not: the provider reads a context that this side has to create,
  and every WebNN entry point stays unset until `Module.webnnInit` is handed a
  backend object. Upstream passes its TypeScript one; this package passes its
  own. Only the parts a session on ordinary tensors reaches are implemented,
  which is all of them so far. The MLTensor paths, where a model's data would
  stay on the accelerator between runs, throw by name if the runtime ever asks.
- **No loading libraries at run time.** Emscripten can do it, with
  `MAIN_MODULE` and side modules, but ONNX Runtime links its web build
  statically and sets neither. So providers and custom operators are compiled
  into the build you serve rather than added as packages.
- **No filesystem in this build.** Emscripten offers several, but ONNX Runtime
  links its web build with `FILESYSTEM=0` to keep it small, so profiling and
  optimized-model output have nowhere to write.
- **No 64-bit integers when compiled to JavaScript.** A Dart `int` is a
  JavaScript number there, so `Int64List` does not exist and the zero-copy
  `view.int64s` refuses. int64 is common in ONNX outputs, indices and token
  ids especially, so there are two portable accessors instead. Reach for
  `view.int64Values` first: it returns a `List<int>` on every platform and is
  free where 64-bit integers are real. It throws on a value beyond 53 bits
  rather than returning a rounded one, since an index that is quietly wrong is
  worse than one that fails. `view.int64BigInts` is exact for any 64-bit value
  and is what to use when they really are that large.
- **Compiled to WebAssembly, the page must be cross-origin isolated.** Every
  runtime we ship is the threaded build, so its heap is a `SharedArrayBuffer`
  whether or not the page can use the threads, and a browser hides that
  constructor unless the page is cross-origin isolated. dart2js never looks,
  so it works either way. dart2wasm checks a buffer's kind before viewing it,
  finds nothing to compare against, and fails an assertion inside the first
  allocation. Serve with COOP and COEP, which is what threads need anyway.
  `test/web_environment_test.dart` checks this and says so when it is wrong.
  Both compilers are tested, and on dart2wasm `view.int64s` works natively.
- **Serve the Asyncify build, not the JSPI one.** ONNX Runtime can be built
  either way, and upstream is moving toward JSPI. This package drives Asyncify:
  it tells the two kinds of build apart by whether the module defines
  `asyncInit`, which a JSPI build does not, so one would be taken for the plain
  synchronous build and its promises read as numbers. Nothing would throw and
  every result would be wrong, so a loader URL containing `.jspi.` is refused
  outright. The same directory publishes the `.asyncify.mjs` build beside it.
- **Threads need a cross-origin isolated page.** The runtime uses real workers,
  which need `SharedArrayBuffer`, which needs COOP and COEP headers. That is
  the page's choice, so the default is the hardware concurrency when the page
  has them and one when it does not: asking for more without them fails to
  start the runtime rather than degrading. `WebRuntimeOptions.threads` overrides
  it.
- **Both forms work on every build; only an accelerator needs the
  asynchronous one.** `Session.load` and `runAsync` work everywhere. So do
  `Session.fromBytes` and `run`, including on the WebGPU and WebNN builds, as
  long as the session stays on the CPU: those builds are compiled with
  Asyncify, but Asyncify only suspends when a call reaches something
  asynchronous, and CPU work never does. What cannot be synchronous is a
  session on an accelerator, because requesting a device and reading results
  back off one are asynchronous, and a synchronous call is holding the event
  loop that would resume it. That case throws and points at `runAsync`. Note that the plain build still blocks the page while a model runs:
  awaiting it does not move the work, it only lets you await it. See
  [Keeping inference off the calling thread](#keeping-inference-off-the-calling-thread).

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
fifty lines and is the whole example.

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

Every function in every API struct is reachable, because ffigen binds the
headers whole. Most also have a generated wrapper taking and returning Dart
values, allocating what the call needs and turning a failed `OrtStatus` into an
`OrtException`. A few dozen do not, where a signature defeats the generator, and
those are listed in `lib/src/bindings/api/unmapped.txt`.

Either way the raw function pointer is there, which is also the way in when a
wrapper cannot express what you need, such as a callback.

`native.dart` also holds what needs the loader rather than the runtime, which is
why provider registration lives there: the shared library has to compile for the
web, and that means no `dart:ffi` above the backend seam.

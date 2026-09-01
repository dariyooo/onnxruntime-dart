# onnxruntime_dart

Run ONNX models from Dart. No Flutter dependency, no platform channels.

Bindings to [ONNX Runtime](https://onnxruntime.ai), generated from pinned
headers. If you have a `.onnx` file, this runs it.

## Install

Two packages: the bindings, and the engine.

```sh
dart pub add onnxruntime_dart onnxruntime_binaries
```

`onnxruntime_dart` ships no binaries. `onnxruntime_binaries` has a build hook
that downloads the right library for the target and bundles it as a code asset.
They are split so you can pin the engine independently, swap in your own build,
or ship none at all.

Without an engine, calls throw `OrtRuntimeMissing` rather than failing to load.

## First inference

A model has named inputs and outputs. Pass a tensor per input, get one back per
output. A tensor is a flat list plus a shape.

```dart
import 'dart:io';
import 'dart:typed_data';
import 'package:onnxruntime_dart/onnxruntime_dart.dart';

void main() {
  final session = Session.fromBytes(File('mnist.onnx').readAsBytesSync());

  for (final input in session.inputs) {
    print(input); // Input3 float32 [1, 1, 28, 28]
  }

  final pixels = Float32List(1 * 1 * 28 * 28);
  final input = OrtTensor.fromData(OrtElementType.float32, pixels, [1, 1, 28, 28]);
  final outputs = session.run({'Input3': input});

  print(outputs['Plus214_Output_0']!.view.float32s);

  input.release();
  for (final output in outputs.values) {
    output.release();
  }
  session.release();
}
```

## Memory

Call `release()` on sessions and tensors. It is the contract, not a suggestion.

A dropped handle is caught by a finalizer, but Dart does not promise finalizers
run, and under load they do not keep up: in a 200,000-iteration loop, zero
fired. Forgetting leaks. It never corrupts, though, because releasing twice or
using a released handle throws.

## Platforms

| Platform | Architectures |
| --- | --- |
| Android | arm64-v8a, armeabi-v7a, x86_64, x86 |
| iOS | device arm64, simulator arm64 and x86_64 |
| macOS | arm64, x86_64 |
| Linux | x86_64, arm64 |
| Windows | x86_64, arm64 |
| Web | not yet, see below |

Every library is built from the pinned submodule, every operator and opset, on
every target. Nothing is trimmed.

### Variants

`base` is the default and is what almost every application wants. `full` adds
what cannot be loaded at runtime and has to be compiled in, which today means
the training APIs.

```yaml
hooks:
  user_defines:
    onnxruntime_binaries:
      variant: full
```

`trainingIsAvailable()` reports which one you have.

### Bring your own

Point the hook at a directory and it bundles that instead:

```yaml
hooks:
  user_defines:
    onnxruntime_binaries:
      local_build: path/to/lib
```

## Execution providers

CPU always works. Anything else is a separate package, because a GPU backend is
tens to hundreds of megabytes and most applications want none of them.

```sh
dart pub add onnxruntime_ep_webgpu
```

```dart
import 'package:onnxruntime_ep_webgpu/onnxruntime_ep_webgpu.dart';

registerWebGpu(); // before any session exists
```

Each provider package installs its library and registers it. Nothing is
discovered by magic, and this package knows about none of them: a test asserts
that no source file here names a provider package.

| Package | Targets |
| --- | --- |
| `onnxruntime_ep_webgpu` | Android arm64 and x86_64, iOS, macOS, Linux, Windows |
| `onnxruntime_ep_cuda` | Linux and Windows x64, arm64 on CUDA 13 |
| `onnxruntime_ep_qnn` | Linux and Windows, both architectures |

WebGPU is built here, reaching Vulkan on Android and Linux, D3D12 or Vulkan on
Windows, and Metal on Apple. CUDA and QNN are mirrored from what ONNX Runtime
publishes: CUDA because building it needs the toolkit and hours of compute, QNN
because the Qualcomm SDK it links against is behind an authenticated download.
The QNN package carries that SDK's runtime with it.

CUDA ships against two toolkits and defaults to 12, which asks less of the
driver. `build: cuda13` selects the other where it exists, which on arm64 is the
only one there is.

For a provider we do not package, `registerProviderLibrary(name:, path:)` takes
any library exporting `CreateEpFactories`. Both calls must happen before the
first session exists: they mutate process-global state.

### Shipping your own

A provider is a shared library exporting `CreateEpFactories`, and nothing about
the ones here is privileged. Ship your own the same way.

The one constraint is that `@Native` needs a compile-time constant asset id, so
it can only be written in the package that owns the asset. That is the whole
reason providers are packages rather than a table here.

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
    // whichever library did, and the runtime gets handed the wrong file.
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
`provider`. `onnxruntime_hook` does that work; `packages/onnxruntime_ep_webgpu`
is thirty lines and is the whole example.

The same shape works for a custom operator library: export `RegisterCustomOps`
instead, and pass the path to `SessionOptions(customOpsLibraries: [...])`.

## Operators the runtime does not have

Tokenizers, text, image and audio preprocessing come from
[onnxruntime-extensions](https://github.com/microsoft/onnxruntime-extensions),
which runs them inside the graph instead of making you rewrite BPE or a mel
spectrogram in Dart.

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

It is a plain shared library exporting `RegisterCustomOps`, so nothing about
this is specific to that project: any library with that entry point works the
same way. Every native target, not the web, where the operators have to be
compiled into the runtime rather than loaded beside it.

## Web

Not working yet. One piece is missing, and it is the last one.

What exists: the API above the backend seam is platform-agnostic and compiles
for the web today, tested on Chrome and Firefox in CI. The WebAssembly runtime
is built for all three accelerator variants and published as Flutter asset
packages (`onnxruntime_web`, `onnxruntime_web_webgpu`,
`onnxruntime_web_webgpu_webnn`).

What does not: the backend that calls into those wasm exports. `OrtCalls` has
38 methods and the web implementation of it is a stub, so anything reaching the
runtime throws `UnsupportedError` naming the reason. Everything that does not
touch the runtime already works there.

## Training

In the `full` variant only, since it is behind a compile-time flag.

```dart
import 'package:onnxruntime_dart/native.dart';

if (trainingIsAvailable()) {
  final api = trainingApi();
}
```

Calling it on a `base` build throws `OrtTrainingUnavailable` rather than
crashing, because `GetTrainingApi` returns null there and that is detectable.

## native.dart

`onnxruntime_dart.dart` is the ergonomic surface, and it is web-safe: no
`dart:ffi` above the backend seam, enforced by a test. `native.dart` holds
everything that needs the loader, which is the full C API plus provider
registration and the training entry points.

```dart
import 'package:onnxruntime_dart/native.dart';
```

Every function in every API struct is generated from the pinned headers, so
completeness is a property of the build rather than a goal. Each has a wrapper
taking and returning Dart values, allocating what the call needs and turning a
failed `OrtStatus` into an `OrtException`. The raw function pointer is still
there when a wrapper cannot express what you need, such as a callback.

## How it fits together

```text
onnxruntime_dart        bindings and the ergonomic API, no binaries
onnxruntime_binaries    the engine, one variant per build
onnxruntime_ep_*        one execution provider each: webgpu, cuda, qnn
onnxruntime_extensions  operators the runtime does not ship
onnxruntime_web*        the wasm builds, as Flutter assets
```

Each is built and released on its own pipeline, so a provider that will not
compile cannot stop the runtime from being built. Every archive is checked
against the SHA-256 published beside it before it is installed.

Nothing depends on Flutter except the web asset packages. The bindings are
generated and checked against the submodule in CI, so they cannot drift from
the headers they were made from.

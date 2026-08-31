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
import 'package:onnxruntime_dart/native.dart';

registerBundledProviders(); // finds every provider package you depend on
```

Provider packages ship no Dart API. They install a library; that call finds it.
It lives in `native.dart` because finding a loaded library means asking the
loader, which needs `dart:ffi`.

| Provider | Targets |
| --- | --- |
| WebGPU | Android arm64 and x86_64, iOS, macOS, Linux, Windows |
| CUDA | Linux and Windows x64, arm64 on CUDA 13 |

WebGPU is built here. CUDA is mirrored from ONNX Runtime's own plugin release,
because building it needs the toolkit and hours of compute. CUDA ships against
two toolkits and defaults to 12, which asks less of the driver; `build: cuda13`
selects the other where it exists.

For a provider we do not package, `registerProviderLibrary(name:, path:)` takes
any library exporting `CreateEpFactories`. Both calls must happen before the
first session exists: they mutate process-global state.

## Web

Not working yet, and the honest version is that only the last step is missing.

Everything above the backend seam is platform-agnostic and compiles for the web
today. The WebAssembly runtime is built and published as Flutter asset packages
(`onnxruntime_web`, `onnxruntime_web_webgpu`, `onnxruntime_web_webgpu_webnn`).
What does not exist is the code binding Dart to the wasm exports, so reaching
the runtime throws `UnsupportedError` saying exactly that.

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
onnxruntime_ep_*        one execution provider each
onnxruntime_web*        the wasm builds, as Flutter assets
```

Nothing depends on Flutter except the web asset packages. The bindings are
generated and checked against the submodule in CI, so they cannot drift from
the headers they were made from.

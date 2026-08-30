# onnxruntime_dart

ONNX Runtime 1.29.0 for Dart. No Flutter dependency, so it runs in CLI tools and
servers as well as apps.

> Unreleased. `native.dart` works today. `Session` is not written yet.

## Install

```yaml
dependencies:
  onnxruntime_dart: ^0.1.0
```

That is the whole setup. A build hook downloads the runtime for your target,
checks it against a pinned SHA-256, and bundles it as a native asset. You do not
place a binary, set a path, or add a platform folder.

## Use

```dart
import 'package:onnxruntime_dart/onnxruntime_dart.dart';

final session = await Session.fromBytes(bytes);
final out = session.runSync({'input': OrtValue.fromList(pixels, [1, 3, 224, 224])});
print(out['output']!.toFloat32List());
session.dispose();
```

## What you get

Every build carries **every operator**: all of `ai.onnx`, `ai.onnx.ml` and the
`com.microsoft` contrib ops, at every opset. No operator is behind a download or
a flag. Fifteen builds, all made from a pinned ONNX Runtime submodule in this
repo's CI.

| Platform | Architecture | Providers | Library |
| --- | --- | --- | --- |
| Android | arm64-v8a | CPU, XNNPACK | `libonnxruntime.so` |
| Android | armeabi-v7a | CPU, XNNPACK | `libonnxruntime.so` |
| Android | x86_64 | CPU, XNNPACK | `libonnxruntime.so` |
| Android | x86 | CPU, XNNPACK | `libonnxruntime.so` |
| iOS | arm64 device | CPU, XNNPACK, CoreML | `libonnxruntime.dylib` |
| iOS | arm64 simulator | CPU, XNNPACK, CoreML | `libonnxruntime.dylib` |
| iOS | x86_64 simulator | CPU, XNNPACK, CoreML | `libonnxruntime.dylib` |
| macOS | arm64 | CPU, XNNPACK, CoreML | `libonnxruntime.dylib` |
| macOS | x86_64 | CPU, XNNPACK, CoreML | `libonnxruntime.dylib` |
| Linux | x64 | CPU, XNNPACK | `libonnxruntime.so` |
| Linux | arm64 | CPU, XNNPACK | `libonnxruntime.so` |
| Windows | x64 | CPU, XNNPACK | `onnxruntime.dll` |
| Windows | arm64 | CPU | `onnxruntime.dll` |
| Web | wasm + SIMD | CPU | `ort-wasm.wasm` |
| Web | wasm + SIMD + threads | CPU | `ort-wasm.wasm` |

About 33 MB per desktop library. Windows arm64 has no XNNPACK: its fp16 kernels
include `arm_fp16.h`, which MSVC does not ship. The threaded wasm build falls
back to one thread when the page is not cross-origin isolated, so ship that one
unless you have a reason not to.

## Packages

Everything above is in the base package. The rest are separate because they are
separate binaries, downloaded only if you ask for them.

| Package | What it is | Size |
| --- | --- | --- |
| `onnxruntime_dart` | The runtime and every operator. | ~33 MB |
| `onnxruntime_dart_ep_webgpu` | A GPU execution provider. A shared library the runtime loads at runtime. Android, Linux, Windows. | ~18 MB |
| `onnxruntime_dart_ep_qnn` | Snapdragon NPU execution provider. Android arm64. | |
| `onnxruntime_dart_extensions` | Custom operators for pre- and post-processing: tokenizers, audio, image decoding. Not model operators. | |

An execution provider changes **where** operators run. It never adds operators.
If a model loads on CPU it loads on every provider.

```
dart pub add onnxruntime_dart_ep_webgpu
```

```dart
import 'package:onnxruntime_dart_ep_webgpu/onnxruntime_dart_ep_webgpu.dart';

registerWebGpu();                     // before any session exists
final session = await Session.fromBytes(model, options: const SessionOptions(
  providers: [Provider.webGpu, Provider.cpu],
));
```

Register providers before creating a session. Registration mutates
process-global runtime state and racing it against session creation crashes.

Contrib ops are not a package and cannot be. They are built into the CPU
provider, and the graph passes that emit them are compiled in beside them.

## Structure

Two libraries.

| Import | Reach | Limit |
| --- | --- | --- |
| `package:onnxruntime_dart/onnxruntime_dart.dart` | all six platforms | what the wasm build exports |
| `package:onnxruntime_dart/native.dart` | native only | all 425 `OrtApi` functions |

`native.dart` is generated from the pinned headers, so it is complete by
construction rather than by effort. Use it for anything the portable API does
not cover:

```dart
import 'package:onnxruntime_dart/native.dart';
final api = ortApi().ref;
```

The portable API cannot simply forward to it, because the WebAssembly build
exposes a different and smaller C surface with no `OrtApi` struct at all. So
everything portable is written against a narrow interface with two
implementations, one over `dart:ffi` and one over the wasm exports. That
interface is the only place either backend appears.

## Concurrency

| | Blocks the caller | Where |
| --- | --- | --- |
| `session.runSync(...)` | yes | everywhere |
| `await session.run(...)` | no | native, needs `intraOpNumThreads >= 2` |
| your own isolate | no | native |

`run` hands the work to ONNX Runtime's own thread pool. No second Dart heap and
no copying.

There is no isolate pool in this package. A `Session` belongs to the isolate
that created it, so create it there and keep it:

```dart
Isolate.spawn(_worker, [port, modelBytes]);   // build once, serve many
```

`Isolate.run(...)` per inference rebuilds the session, and session creation runs
graph optimisation.

Web has neither. `dart:isolate` is unavailable under dart2js and dart2wasm, and
the wasm build has no async entry point, so `runSync` blocks. Run your app in a
Web Worker.

## Versioning

`X.Y.Z+onnxruntime-A.B.C`. The suffix is the ONNX Runtime version, and always
matches the submodule this repo pins.

## License

MIT, as is ONNX Runtime.

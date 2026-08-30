# onnxruntime_dart

Pure-Dart bindings to [ONNX Runtime](https://onnxruntime.ai). No Flutter
dependency, so it runs in CLI tools and servers as well as apps.

> **Status:** unreleased. `native.dart` works today. The ergonomic `Session` API
> below is being written.

## Quickstart

```yaml
dependencies:
  onnxruntime_dart: ^0.1.0
```

The runtime is downloaded and bundled by a build hook. There is no binary to
place and no path to configure.

```dart
import 'package:onnxruntime_dart/onnxruntime_dart.dart';

final session = await Session.fromBytes(await File('model.onnx').readAsBytes());
final outputs = session.runSync({'input': OrtValue.fromList(pixels, [1, 3, 224, 224])});
print(outputs['output']!.toFloat32List());
session.dispose();
```

Anything the ergonomic API does not cover yet is reachable through the complete
C API, which is generated from the pinned headers:

```dart
import 'package:onnxruntime_dart/native.dart';

final api = ortApi().ref;   // all 425 OrtApi functions
```

## Async and isolates

`runSync` is the primitive. It is the only call both native and web have, and it
blocks the calling thread. Two ways to not block, and the package makes neither
your only option.

**`run` (native only).** Returns a `Future` backed by ONNX Runtime's own
intra-op thread pool. No second Dart heap, no copying, and the calling isolate
stays responsive. Requires `intraOpNumThreads >= 2`, which is checked up front.

**Your own isolate.** The package ships no isolate pool, deliberately. A pool
inside a library guesses wrong about your workload, and only you know whether
inference sits next to image decode or a request handler. What the package owes
you is that a session works anywhere, which it does.

```dart
// Right: build once, serve many. Session creation runs graph optimisation.
Isolate.spawn(_worker, [port, modelBytes]);

// Wrong: rebuilds the session, and re-optimises the graph, on every call.
await Isolate.run(() => Session.fromBytes(bytes).runSync(inputs));
```

A `Session` belongs to the isolate that created it. Create it there rather than
passing one across.

**On web there is neither.** `dart:isolate` is unavailable under dart2js and
dart2wasm, and ONNX Runtime's async entry point is not in the wasm build, so
`runSync` blocks. Running your app in a Web Worker is the answer, and that is
your call to make, not this package's.

## Packages

The base package carries **every operator**. Nothing you need for inference is
behind an extra download.

| Package | Contains |
| --- | --- |
| `onnxruntime_dart` | `ai.onnx`, `ai.onnx.ml`, `com.microsoft` contrib ops. CPU, plus XNNPACK and CoreML where they apply. |
| `onnxruntime_dart_ep_webgpu` | GPU execution provider. Loaded at runtime, not linked. |
| `onnxruntime_dart_ep_qnn` | Snapdragon NPU. Android, opt-in download. |
| `onnxruntime_dart_extensions` | Pre- and post-processing operators: tokenizers, audio, vision. Not model operators. |

Contrib ops are **not** an optional package. They are built into the CPU
provider and the graph passes that emit them are compiled in beside them, so
splitting them would produce graphs referencing operators that do not exist.

An execution provider is a shared library the runtime opens by path:

```dart
import 'package:onnxruntime_dart_ep_webgpu/onnxruntime_dart_ep_webgpu.dart';

registerWebGpu();                       // adds its devices to the environment
final session = await Session.fromBytes(model, options: SessionOptions(
  providers: [Provider.webGpu, Provider.cpu],
));
```

Register providers before creating any session. Registration mutates
process-global runtime state and racing it against session creation crashes.

## Versioning

`X.Y.Z+onnxruntime-<version>`. The suffix names the ONNX Runtime release the
package binds, and always matches the pinned submodule.

## License

MIT, as is ONNX Runtime. See [LICENSE](LICENSE).

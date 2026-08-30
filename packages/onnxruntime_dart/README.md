# onnxruntime_dart

Run ONNX machine-learning models in Dart, on any platform, without Flutter.

Wraps [ONNX Runtime](https://onnxruntime.ai), Microsoft's inference engine. If
you have a `.onnx` file, this runs it.

## Install

```
dart pub add onnxruntime_dart
```

A build hook downloads and bundles the engine for native targets, and on the web
you serve the `.wasm` yourself.

## Your first inference

A model has named inputs and outputs. You pass a tensor for each input and get
one back per output. A tensor is a flat list plus a shape.

```dart
import 'dart:io';
import 'package:onnxruntime_dart/onnxruntime_dart.dart';

void main() async {
  final session = await Session.fromBytes(
    await File('mnist.onnx').readAsBytes(),
  );

  // What does this model want? Names and shapes come from the model itself.
  for (final input in session.inputs) {
    print('${input.name} ${input.shape} ${input.type}');   // Input3 [1, 1, 28, 28] float32
  }

  // 1x1x28x28 means one image, one channel, 28 by 28. 784 floats, flat.
  final pixels = Float32List(1 * 1 * 28 * 28);

  final outputs = session.runSync({
    'Input3': OrtValue.fromList(pixels, [1, 1, 28, 28]),
  });

  final scores = outputs['Plus214_Output_0']!.toFloat32List();
  print('digit ${_argmax(scores)}');

  session.dispose();
}
```

`dispose` frees the model. Skipping it leaks about as much memory as the model
weighs.

### Shapes

One entry per dimension, outermost first. `[1, 3, 224, 224]` is one image, three
colour channels, 224 by 224, so the flat list holds 150 528 values. A `-1` means
the model decides that dimension at run time, usually batch size.

### Types

`OrtValue.fromList` takes the typed list and matches the tensor type to it.

| Dart | ONNX |
| --- | --- |
| `Float32List` | float32 |
| `Int64List` | int64 |
| `Int32List` | int32 |
| `Uint8List` | uint8 |

Float64, float16, int8, int16, bool and string are supported too.

## Platforms

Every build carries **every operator**: all of `ai.onnx`, `ai.onnx.ml` and the
`com.microsoft` contrib ops, at every opset. A model that loads anywhere loads
everywhere. All libraries are built in this repo's CI from a pinned ONNX
Runtime.

| Platform | Architectures |
| --- | --- |
| Android | arm64-v8a, armeabi-v7a, x86_64, x86 |
| iOS | arm64 device, arm64 simulator, x86_64 simulator |
| macOS | arm64, x86_64 |
| Linux | x64, arm64 |
| Windows | x64, arm64 |
| Web | wasm, three accelerator builds |

## Web

A browser cannot open a shared library, so every accelerator is compiled into
the `.wasm`. There is no provider package and no `register` call: you choose
accelerators by choosing which build you serve.

Take a build from this repo's releases, serve it with your app, and point the
package at it:

```dart
await Ort.initWeb(wasmUrl: '/assets/ort-wasm-webgpu.wasm');
```

| Build | Accelerators |
| --- | --- |
| `ort-wasm` | XNNPACK |
| `ort-wasm-webgpu` | XNNPACK, WebGPU |
| `ort-wasm-webgpu-webnn` | XNNPACK, WebGPU, WebNN |

Smaller is faster to download, so take the one you need. All three are threaded
and fall back to a single thread when the page is not cross-origin isolated. For
threads, set `Cross-Origin-Opener-Policy: same-origin` and
`Cross-Origin-Embedder-Policy: require-corp`.

## Execution providers

An execution provider decides **where** operators run. It never adds operators,
so switching to one cannot make a model load that did not load before.

A provider is a second shared library beside the engine, and ONNX Runtime opens
it by path at run time. Any library exporting `CreateEpFactories` works,
including ones you build or get elsewhere:

```dart
Ort.registerProvider(name: 'cuda', path: '/opt/ort/libonnxruntime_providers_cuda.so');

final session = await Session.fromBytes(model, options: const SessionOptions(
  providers: [Provider.named('cuda'), Provider.cpu],   // cuda first, cpu as fallback
));
```

Register providers before creating a session. Registration mutates
process-global state and racing it against session creation crashes.

| Provider | Android | iOS | macOS | Linux | Windows | Web |
| --- | --- | --- | --- | --- | --- | --- |
| CPU | built in | built in | built in | built in | built in | built in |
| XNNPACK | built in | built in | built in | built in | built in | built in |
| CoreML | | built in | built in | | | |
| WebGPU | package | | | package | package | build variant |
| WebNN | | | | | | build variant |
| QNN | package, arm64 | | | | | |
| CUDA, TensorRT, OpenVINO, CANN, ROCm | | | | you supply | you supply | |

**built in** costs you nothing and is used automatically. **package** is a
separate download:

```
dart pub add onnxruntime_dart_ep_webgpu
```

```dart
import 'package:onnxruntime_dart_ep_webgpu/onnxruntime_dart_ep_webgpu.dart';

registerWebGpu();   // the same call as above, with the path filled in
```

**build variant** means the web, where the choice is which `.wasm` you serve.
**you supply** means we will not package it: each targets one vendor's hardware,
and neither we nor Microsoft build those for every platform.

There is also `onnxruntime_dart_extensions`, which adds operators for the work
around a model rather than in it: tokenizers, audio decoding, image resizing.

## Keeping the UI responsive

`runSync` blocks the thread it is called on. A large model will freeze your UI.

```dart
final outputs = await session.run(inputs);     // returns to you immediately
```

`run` hands the work to ONNX Runtime's own threads. Nothing is copied and no
isolate is spawned.

To move your own pre- and post-processing off the UI thread too, run the whole
pipeline in an isolate. Build the session inside it and keep it, because
creating one optimises the model graph:

```dart
Isolate.spawn(_worker, [replyPort, modelBytes]);
```

Do not call `Isolate.run` per inference. That rebuilds the session every time.

Neither works on the web. Dart has no isolates there and the WebAssembly build
has no background entry point, so `runSync` blocks and `run` throws. Run the
whole app in a Web Worker instead.

## On-device training

Training has to be compiled in, so it comes as a second library rather than a
package. Ask for it once:

```yaml
hooks:
  user_defines:
    onnxruntime_dart:
      variant: full
```

That swaps the bundled engine for one built with the training APIs: checkpoints,
train and optimizer steps, and exporting an inference model when you are done.
Everything else is identical, so nothing else in your code changes.

`Ort.trainingAvailable` reports which library you got, rather than failing at the
first call.

## Raw C API

The Dart API covers ONNX Runtime's C API. Where the web cannot support a call it
is marked, and throws there, rather than being left out everywhere:

```dart
@NativeOnly('the WebAssembly build exports no asynchronous run')
Future<Map<String, OrtValue>> run(Map<String, OrtValue> inputs);
```

So the limit is in the signature and in the docs, not something you find by
hitting it. Web supports a smaller C surface than native, and shrinking the API
to their intersection would make web's limits everyone's.

For interop with other native code, the generated bindings are also exported.
They are produced from the same headers the libraries are built from, so they
never lag the engine:

```dart
import 'package:onnxruntime_dart/native.dart';

final api = ortApi().ref;
```

Native only, and you own every handle you create.

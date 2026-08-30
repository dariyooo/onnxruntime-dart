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

| Platform | Architecture | Accelerators |
| --- | --- | --- |
| Android | arm64-v8a, armeabi-v7a, x86_64, x86 | XNNPACK |
| iOS | arm64 device, arm64 simulator, x86_64 simulator | XNNPACK, CoreML |
| macOS | arm64, x86_64 | XNNPACK, CoreML |
| Linux | x64, arm64 | XNNPACK |
| Windows | x64 | XNNPACK |
| Windows | arm64 | none |
| Web | wasm + SIMD, and a threaded build | none |

Everything runs on CPU. The accelerators are compiled in and used automatically.
Windows arm64 has no XNNPACK because its fp16 kernels need `arm_fp16.h`, which
MSVC does not ship.

## Web

The web works differently, and the difference is worth knowing before you plan
around it.

Nothing is loaded at run time. A browser cannot open a shared library, so
everything the engine can do is compiled into the `.wasm` itself. There is no
provider package for the web and no `register` call. **You choose your
accelerators by choosing which build you serve.**

Take a build from this repo's releases, serve it with your app, and point the
package at it:

```dart
await Ort.initWeb(wasmUrl: '/assets/ort-wasm-simd-threaded.wasm');
```

| Build | Runs on |
| --- | --- |
| `ort-wasm-simd` | CPU |
| `ort-wasm-simd-threaded` | CPU, several threads |

The threaded build falls back to one thread when the page is not cross-origin
isolated, so serve it unless you have a reason not to. Threads need
`Cross-Origin-Opener-Policy: same-origin` and
`Cross-Origin-Embedder-Policy: require-corp` on the page.

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

Two are packaged for convenience, so you do not fetch or version them yourself:

| Package | Runs work on | Platforms |
| --- | --- | --- |
| `onnxruntime_dart_ep_webgpu` | GPU | Android, Linux, Windows |
| `onnxruntime_dart_ep_qnn` | Snapdragon NPU | Android arm64 |

```
dart pub add onnxruntime_dart_ep_webgpu
```

```dart
import 'package:onnxruntime_dart_ep_webgpu/onnxruntime_dart_ep_webgpu.dart';

registerWebGpu();   // the same call, with the path filled in for you
```

Everything else, CUDA, TensorRT, OpenVINO and the rest, you supply. Microsoft
ships those as separate downloads too, and building every provider for every
platform is not something anyone does.

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

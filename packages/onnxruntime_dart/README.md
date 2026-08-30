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

On the web, take the `.wasm` from this repo's releases and serve it with your
app. The threaded build falls back to one thread when the page is not
cross-origin isolated, so ship that one unless you have a reason not to.

## Going faster on a GPU or NPU

An execution provider decides **where** operators run. It never adds operators,
so switching to one cannot make a model load that did not load before.

They are separate packages because they are separate binaries.

```
dart pub add onnxruntime_dart_ep_webgpu
```

```dart
import 'package:onnxruntime_dart_ep_webgpu/onnxruntime_dart_ep_webgpu.dart';

void main() async {
  registerWebGpu();                       // once, before any session

  final session = await Session.fromBytes(model, options: const SessionOptions(
    providers: [Provider.webGpu, Provider.cpu],   // GPU first, CPU as fallback
  ));
}
```

| Package | Runs work on | Platforms |
| --- | --- | --- |
| `onnxruntime_dart_ep_webgpu` | GPU | Android, Linux, Windows |
| `onnxruntime_dart_ep_qnn` | Snapdragon NPU | Android arm64 |

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

## When you need something this API does not have

Every function in ONNX Runtime's C API is available, generated from the same
headers the libraries are built from:

```dart
import 'package:onnxruntime_dart/native.dart';

final api = ortApi().ref;
```

Native only. The WebAssembly build exposes a different, smaller C surface, so
anything reached this way will not compile for the web.

## Versioning

`X.Y.Z+onnxruntime-A.B.C`. The part after `+` is the ONNX Runtime version the
package binds, so the engine version is always visible in the package version.

## License

MIT, as is ONNX Runtime.

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
import 'dart:typed_data';
import 'package:onnxruntime_dart/onnxruntime_dart.dart';

void main() {
  final session = Session.fromBytes(File('mnist.onnx').readAsBytesSync());

  // What does this model want? Names and shapes come from the model itself.
  for (final input in session.inputs) {
    print(input);   // Input3 float32 [1, 1, 28, 28]
  }

  // 1x1x28x28 means one image, one channel, 28 by 28. 784 floats, flat.
  final pixels = Float32List(1 * 1 * 28 * 28);
  final input = OrtTensor.fromData(
    OrtElementType.float32,
    pixels,
    [1, 1, 28, 28],
  );

  final outputs = session.run({'Input3': input});
  final scores = outputs['Plus214_Output_0']!.view.float32s;
  print('digit ${_argmax(scores)}');

  input.release();
  for (final output in outputs.values) {
    output.release();
  }
  session.release();
}
```

`release` frees a session or a tensor now. Dropping the last reference frees it
too, whenever the garbage collector gets there, so forgetting costs a delay
rather than a leak.

### Shapes

One entry per dimension, outermost first. `[1, 3, 224, 224]` is one image, three
colour channels, 224 by 224, so the flat list holds 150 528 values. A `-1` means
the model decides that dimension at run time, usually batch size.

### Types

`OrtTensor.fromData` takes the element type, a typed list, and the shape.
`view` reads one back, and asks for the type you expect rather than
reinterpreting the bytes.

| ONNX | write | read |
| --- | --- | --- |
| float32 | `Float32List` | `view.float32s` |
| float64 | `Float64List` | `view.float64s` |
| int8, int16, int32, int64 | the matching `IntNList` | `view.intNs` |
| uint8, uint16, uint32, uint64 | the matching `UintNList` | `view.uintNs` |
| bool | `Uint8List`, one byte each | `view.bools` |
| float16 | `Uint16List` of raw bits | `view.float16Bits` |
| string | `OrtTensor.fromStrings` | `tensor.strings` |

`view.data` is the raw bytes if you would rather do it yourself. It borrows the
tensor's own memory, so copy it if it needs to outlive the tensor.

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

**Not working yet.** The library compiles for the browser and everything that
does not touch the runtime works there, but nothing binds the WebAssembly
exports, so creating a session throws. The builds below exist; the code that
loads them does not.

A browser cannot open a shared library, so every accelerator is compiled into
the `.wasm`. There is no provider package and no `register` call: you choose
accelerators by choosing which build you serve.

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
registerProviderLibrary(
  name: 'cuda',
  path: '/opt/ort/libonnxruntime_providers_cuda.so',
);

final session = Session.fromBytes(model, options: const SessionOptions(
  providers: [(name: 'cuda', configuration: {})],
));
```

Register providers before creating a session. Registration mutates
process-global state and racing it against session creation crashes.

`availableProviders()` lists what your build has compiled in.

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
separate download, and none of those packages exist yet:

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

`onnxruntime_dart_extensions` is planned too, adding operators for the work
around a model rather than in it: tokenizers, audio decoding, image resizing.

## Keeping the UI responsive

`run` blocks the thread it is called on. A large model will freeze your UI.

```dart
final outputs = await session.runAsync(inputs);   // returns to you immediately
```

`runAsync` hands the work to ONNX Runtime's own threads and completes on your
event loop. Nothing is copied and no isolate is spawned, so one session can
have several runs in flight against one copy of the weights.

It needs at least two intra-op threads, since that pool is what it dispatches
onto. `SessionOptions(intraOpNumThreads: 1)` rules it out, and says so.

To move your own pre- and post-processing off the UI thread too, run the whole
pipeline in an isolate. Build the session inside it and keep it, because
creating one optimises the model graph:

`example/isolates.dart` has both patterns, the short-lived one and the worker.
Do not call `Isolate.run` per inference: that rebuilds the session every time.

Neither works on the web. Dart has no isolates there and the WebAssembly build
has no background entry point, so `run` blocks and `runAsync` throws. Run the
whole app in a Web Worker instead.

## On-device training

**Not working yet.** The library with the training APIs builds, but nothing
binds them.

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

## Raw C API

The Dart API covers ONNX Runtime's C API. Where the web cannot support a call it
is marked, and throws there, rather than being left out everywhere:

```dart
@NativeOnly('the WebAssembly build exports no asynchronous run')
Future<Map<String, OrtTensor>> runAsync(Map<String, OrtTensor> feeds);
```

So the limit is in the signature and in the docs, not something you find by
hitting it. Web supports a smaller C surface than native, and shrinking the API
to their intersection would make web's limits everyone's.

The whole C API is there when the Dart API does not cover something. Both the
bindings and a wrapper for each call are generated from the same headers the
libraries are built from, so neither lags the engine:

```dart
import 'package:onnxruntime_dart/native.dart';

final api = ortApi().ref;
final allocator = api.getAllocatorWithDefaultOptions();
final name = api.sessionGetInputName(session, 0, allocator);
```

Each wrapper takes and returns Dart values, and turns a failed `OrtStatus` into
an `OrtException`. The raw function pointer is still there for the handful of
calls a wrapper cannot express, such as ones taking a callback.

Native only, and you own every handle you create.

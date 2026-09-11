# Running on the web

Everything in this package works in a browser, but two things are different
enough to be worth reading before you start.

The runtime is a WebAssembly module that has to be downloaded, and a download
cannot happen synchronously, so you tell `openOnnxRuntime` where to find it.
And there are three builds of that module, differing in which accelerators are
compiled in. Which one you serve decides whether you can use the synchronous
API or have to use the asynchronous one.

If you only want the short version: depend on `onnxruntime_web`, call
`openOnnxRuntime` with its loader URL, and use `Session.load` and `runAsync`.
That combination works on every build and every platform.

## Getting started

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

## Choosing a build at run time

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

## Limitations, and why they exist

None of these fail silently. Each one throws with a message naming the reason,
so you find out at the call rather than from a wrong answer.

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
  loop that would resume it. That case throws and points at `runAsync`.

Awaiting a result does not move the work off the page. Even on the plain build,
a model that takes a second blocks the page for a second. To keep the page
responsive, run the model in a worker: see
[Keeping inference off the calling thread](../README.md#keeping-inference-off-the-calling-thread).

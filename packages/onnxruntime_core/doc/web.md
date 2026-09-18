# Running on the web

Everything in this package works in a browser. Two things are different, and
both are worth reading before you start.

The runtime is a WebAssembly module that has to be downloaded, and a download
cannot be synchronous, so you tell `openOnnxRuntime` where to find it. There are
also three builds of that module, each with different accelerators compiled in.
The build you serve decides whether you can use the synchronous API.

If you want the short version: depend on `onnxruntime_web`, call
`openOnnxRuntime` with its loader URL, and use `Session.load` and `runAsync`.
That works on every build and every platform.

## Getting started

```sh
dart pub add onnxruntime_web
```

```dart
import 'package:onnxruntime_web/onnxruntime_web.dart' as ort_assets;

await openOnnxRuntime(web: WebRuntimeOptions(ort_assets.ortLoaderUrl));
```

One URL is enough, because the runtime looks for its `.wasm` next to the `.mjs`
and the asset packages ship them together. If a bundler moves them apart, pass
`wasm:` as well. If you already have the module in memory, pass `wasmBytes:`.

There are three builds. You choose one by which package you depend on:

| Package | Accelerators | How you call it |
| --- | --- | --- |
| `onnxruntime_web` | XNNPACK | either form |
| `onnxruntime_web_webgpu` | XNNPACK, WebGPU | `Session.load` and `runAsync` |
| `onnxruntime_web_webgpu_webnn` | XNNPACK, WebGPU, WebNN | `Session.load` and `runAsync` |

The two accelerator builds are compiled with Asyncify, because reading results
back off a GPU is asynchronous. This changes how you call them, not how fast
they are: creating a session or running one can suspend and return a promise.
The package detects which build it loaded, and the synchronous calls throw on an
accelerator build rather than mistaking a promise for a result.

`Session.load` and `runAsync` work on every build and on every platform, and
complete immediately where nothing needs to suspend. Use them if your code has
to run on more than one build.

## Choosing a build at run time

You do not have to choose a build at compile time. `openOnnxRuntime` takes a
URL, so a page can check what the browser supports and fetch the matching
build:

```dart
final gpu = web.window.navigator.has('gpu');
await openOnnxRuntime(
  web: WebRuntimeOptions(gpu ? webgpuLoaderUrl : plainLoaderUrl),
);
```

Serve the files yourself if you do this. Depending on all three asset packages
would bundle every build into the app.

You cannot load an accelerator separately, and that is ONNX Runtime's decision
rather than ours. It links WebGPU and WebNN into the WebAssembly module and
injects their JavaScript at link time, so there is no library to load.

## Limitations, and why they exist

None of these fail silently. Each one throws with a message naming the reason,
so you find out at the call rather than from a wrong answer.

- **WebNN needs some JavaScript, which this package supplies.** WebGPU's
  implementation is inside the WebAssembly module, so requesting it is enough.
  WebNN's is not. The provider reads a context that the Dart side has to
  create, and every WebNN entry point stays unset until `Module.webnnInit`
  receives a backend object. Upstream passes its TypeScript one, and this
  package passes its own. Everything a session on ordinary tensors needs is
  implemented. The MLTensor paths, where a model's data would stay on the
  accelerator between runs, throw by name if the runtime asks for them.
- **You cannot load a library at run time.** Emscripten supports it through
  `MAIN_MODULE` and side modules, but ONNX Runtime links its web build
  statically and uses neither. Providers and custom operators are therefore
  compiled into the build you serve rather than added as packages.
- **There is no filesystem.** Emscripten offers several, but ONNX Runtime links
  its web build with `FILESYSTEM=0` to keep it small. Profiling output and
  optimized-model output have nowhere to write.
- **There are no 64-bit integers when you compile to JavaScript.** A Dart `int`
  is a JavaScript number there, so `Int64List` does not exist and the zero-copy
  `view.int64s` throws. int64 is common in ONNX outputs, especially indices and
  token ids, so there are two portable accessors instead. Use
  `view.int64Values` first. It returns a `List<int>` on every platform and
  costs nothing where 64-bit integers are real, and it throws on a value above
  53 bits rather than rounding it, because an index that is quietly wrong is
  worse than one that fails. Use `view.int64BigInts` when the values really are
  that large.

- **If you compile to WebAssembly, the page must be cross-origin isolated.**
  Every runtime we ship is the threaded build, so its heap is a
  `SharedArrayBuffer` whether or not the page uses threads, and browsers hide
  that constructor unless the page is cross-origin isolated. dart2js never
  looks at the buffer type, so it works either way. dart2wasm checks it before
  viewing, finds nothing to compare against, and fails an assertion during the
  first allocation. Serve with COOP and COEP headers, which threads need
  anyway. `test/web_environment_test.dart` checks for this and reports it
  clearly. Both compilers are tested, and on dart2wasm `view.int64s` works.

- **Serve the Asyncify build, not the JSPI one.** ONNX Runtime can be built
  either way and upstream is moving toward JSPI. This package drives Asyncify.
  It tells the builds apart by whether the module defines `asyncInit`, which a
  JSPI build does not, so a JSPI build would be mistaken for the plain
  synchronous one and its promises read as numbers. Nothing would throw and
  every result would be wrong, so a loader URL containing `.jspi.` is rejected.
  The `.asyncify.mjs` build is published in the same directory.

- **Threads need a cross-origin isolated page.** The runtime uses real workers,
  which need `SharedArrayBuffer`, which needs COOP and COEP headers. Whether to
  send those is the page's decision, so the thread count defaults to the
  hardware concurrency when the page is isolated and to one when it is not.
  Asking for more without isolation fails to start the runtime rather than
  degrading quietly. `WebRuntimeOptions.threads` overrides the default.

- **Only an accelerator requires the asynchronous API.** `Session.load` and
  `runAsync` work everywhere. So do `Session.fromBytes` and `run`, including on
  the WebGPU and WebNN builds, as long as the session stays on the CPU. Those
  builds use Asyncify, but Asyncify only suspends when a call reaches something
  asynchronous, and CPU work never does. What cannot be synchronous is a
  session on an accelerator: requesting a device and reading results back are
  both asynchronous, and a synchronous call is holding the event loop that
  would resume them. That case throws and points you at `runAsync`.

Awaiting a result does not move the work off the page. Even on the plain build,
a model that takes a second blocks the page for a second. To keep the page
responsive, run the model in a worker. See
[Keeping inference off the calling thread][off-thread] in the package readme.

[off-thread]: ../README.md#keeping-inference-off-the-calling-thread

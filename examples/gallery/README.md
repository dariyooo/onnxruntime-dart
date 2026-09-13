# ONNX Runtime gallery

A Flutter app that runs six ONNX models and shows which execution provider ran
each one.

It is a test app more than a demo. It uses the packages the way a real
application does: the build hooks install the runtime, the models are
downloaded at startup instead of being bundled, and each run is measured rather
than assumed.

## The models

| Model | Kind | Size | From |
| --- | --- | --- | --- |
| SqueezeNet 1.1 | classifier | 4.8 MB | ONNX Model Zoo |
| MobileNet v2 | classifier | 13 MB | ONNX Model Zoo |
| Tiny YOLOv3 | object detector | 34 MB | ONNX Model Zoo |
| BiDAF | recurrent, LSTM | 42 MB | ONNX Model Zoo |
| all-MiniLM-L6-v2 | transformer | 86 MB | sentence-transformers |
| Phi-3 mini 4k instruct | generative | 2.5 GB | Microsoft |

Each size covers everything the model needs: the ImageNet labels for the
classifiers, the vocabulary for MiniLM, and the tokenizer and weights for
Phi-3. The app shows the size before the download starts, and checks it
afterwards. A file that arrives at the wrong size is discarded instead of run.

Every model is downloaded from the project that published it. Nothing is
converted or re-hosted here, so the behaviour you see is ONNX Runtime's.

## Which provider ran

Asking for a provider is not the same as getting it. ONNX Runtime assigns nodes
to providers one at a time, and a provider that cannot handle a node leaves it
on the CPU without reporting it. A session created with WebGPU requested can
run entirely on the CPU and look no different from one that did not.

Every session runs with profiling enabled. The profile records which provider
executed each node, so the panel below each run shows the actual split, and
says so when a requested provider ran nothing.

## On the web

The app is compiled with `--wasm`, so Dart runs as WebAssembly in browsers that
support WasmGC, and as JavaScript in the rest.

The provider panel is most useful here. The bundled runtime includes XNNPACK,
WebGPU and WebNN, so all three can be requested and the panel shows which one
took the work.

Two things are different in a browser, and the app says so rather than letting
you find out. Models are kept only for the lifetime of the tab, because a
browser has nowhere to store them, so reloading downloads them again. And Phi-3
does not run, because GenAI has no WebAssembly build.

## Running it

```
flutter run
```

`onnxruntime_binaries` downloads the runtime during the first build. Two of the
packages this app uses have no published release yet, so you need to point
their build hooks at a local build. Add this to `pubspec.yaml`, with the paths
changed to match where your builds are:

```yaml
hooks:
  user_defines:
    onnxruntime_genai_binaries:
      local_build: ../../.local/genai/current/lib
    onnxruntime_ep_webgpu_binaries:
      local_build: ../../.local/ort/current/lib
```

This is not committed on purpose. A `local_build` path that does not exist is a
build error rather than a fallback, so committing it would break a fresh
checkout on a machine without those builds.

Without it, everything except Phi-3 and the WebGPU provider works from the
published runtime.

## Tests

```
flutter test
```

The tests run offline. The models are between 5 MB and 2.5 GB, so the app does
not run them as part of the suite. The tests cover the model catalogue, where
the models are downloaded from, the size arithmetic, the profile reader that
tells a CPU fallback from a real accelerated run, the WordPiece tokenizer, the
similarity scoring and the in-memory model store used on the web.

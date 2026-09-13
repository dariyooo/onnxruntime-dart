# ONNX Runtime gallery

A Flutter app that runs six ONNX models and shows which execution provider ran
each one.

It is a test app more than a demo. It uses the packages the way a real
application does: the build hooks install the runtime, and models are downloaded
at startup instead of being bundled.

## The models

| Model | Kind | Size | From |
| --- | --- | --- | --- |
| SqueezeNet 1.1 | classifier | 4.8 MB | ONNX Model Zoo |
| MobileNet v2 | classifier | 13 MB | ONNX Model Zoo |
| Tiny YOLOv3 | object detector | 34 MB | ONNX Model Zoo |
| BiDAF | recurrent, LSTM | 42 MB | ONNX Model Zoo |
| all-MiniLM-L6-v2 | transformer | 86 MB | sentence-transformers |
| Phi-3 mini 4k instruct | generative | 2.5 GB | Microsoft |

Each size includes the labels, vocabulary or tokenizer the model needs. Every
model is downloaded from the project that published it, so nothing is converted
or re-hosted here.

## Which provider ran

Asking for a provider is not the same as getting it. ONNX Runtime assigns nodes
to providers one at a time, and a provider that cannot handle a node leaves it
on the CPU without reporting it. A session created with WebGPU requested can run
entirely on the CPU and look no different from one that did not.

Every session runs with profiling enabled, and the panel below each run shows
what the profile recorded: how many nodes each provider took, and the order
execution moved between them.

```
cpu (60) -> webgpu (400) -> cpu (1) -> webgpu (140)
```

The order matters more than the totals. Each crossing copies tensors between
providers, so a model that alternates can be slower than one that stays on the
CPU throughout, even though the totals look good.

## On the web

The app is compiled with `--wasm`. The bundled runtime includes XNNPACK, WebGPU
and WebNN, so all three can be requested.

Two things differ in a browser. Models are kept only for the lifetime of the
tab, so reloading downloads them again. And Phi-3 does not run, because GenAI
has no WebAssembly build.

## Running it

```
flutter run
```

Two of the packages this app uses have no published release yet, so point their
build hooks at a local build by adding this to `pubspec.yaml`:

```yaml
hooks:
  user_defines:
    onnxruntime_genai_binaries:
      local_build: ../../.local/genai/current/lib
    onnxruntime_ep_webgpu_binaries:
      local_build: ../../.local/ort/current/lib
```

This is not committed, because a `local_build` path that does not exist is a
build error rather than a fallback. Without it, everything except Phi-3 and the
WebGPU provider works from the published runtime.

## Tests

```
flutter test
```

The tests run offline and do not run the models. They cover the catalogue, the
download sizes, the profile reader, the WordPiece tokenizer, similarity scoring
and the in-memory store used on the web.

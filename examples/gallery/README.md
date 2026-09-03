# ONNX Runtime gallery

Runs a spread of upstream ONNX models and reports which execution provider
actually served each one.

It exists to exercise the packages rather than to demonstrate them. Everything
in it is a path a real application takes: the build hooks install the runtime,
the models are fetched at runtime rather than bundled, and each run is
accounted for node by node instead of being assumed to have gone the way it was
asked to.

## What is in it

| Model | Kind | Size | From |
| --- | --- | --- | --- |
| SqueezeNet 1.1 | classifier | 5.0 MB | ONNX Model Zoo |
| MobileNet v2 | classifier | 14 MB | ONNX Model Zoo |
| Tiny YOLOv3 | object detector | 35 MB | ONNX Model Zoo |
| BiDAF | recurrent, LSTM | 43 MB | ONNX Model Zoo |
| all-MiniLM-L6-v2 | transformer | 90 MB | sentence-transformers |
| Phi-3 mini 4k instruct | generative | 2.5 GB | Microsoft |

Every one is fetched from the project that published it. Nothing is converted
here and nothing is hosted here, because a converted model is one whose
behaviour this project would have to explain rather than ONNX Runtime's.

Sizes are shown before a download starts, checked when it finishes, and a file
that arrives a different length than the catalogue promised is discarded rather
than run.

## Which provider actually ran

Asking for a provider and getting it are different things. ONNX Runtime assigns
nodes to providers one at a time, and a provider that cannot take a node leaves
it on the CPU without saying so. A session created with WebGPU requested can
therefore run entirely on the CPU and look, from the outside, exactly like one
that got what it asked for.

Each session is created with profiling on. The profile names the provider that
executed each node, so the panel under every run reports the split rather than
the request, and says plainly when a requested provider took nothing.

## Running it

```
flutter run
```

The runtime arrives through `onnxruntime_binaries`' build hook, which downloads
it on the first build. Two of the packages this app depends on have no published
release yet, so their hooks need to be pointed at a local build. Append this to
`pubspec.yaml`, with the paths adjusted to wherever the builds are:

```yaml
hooks:
  user_defines:
    onnxruntime_genai_binaries:
      local_build: ../../.local/genai/current/lib
    onnxruntime_ep_webgpu_binaries:
      local_build: ../../.local/ort/current/lib
```

It is deliberately not committed: pointing at a directory that does not exist is
a build failure rather than a fallback, so it would break a fresh checkout on a
machine that has no local build.

Without it, everything except Phi-3 and the WebGPU provider works from the
published runtime alone.

## Tests

```
flutter test
```

Offline. The models are between five megabytes and two and a half gigabytes, so
the runs themselves are not part of the suite. What is covered is the catalogue,
the size arithmetic, the profile reader that tells a fallback apart from a real
run, and the WordPiece tokenizer.

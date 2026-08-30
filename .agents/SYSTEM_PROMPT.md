# onnxruntime_dart

Instructions for agents working in this repository.

Pure-Dart FFI bindings to ONNX Runtime. No Flutter dependency. Runs under `dart test`.

## Commands

Run `./tool/check.sh` before pushing. It is everything CI checks, in order,
and the static job gates the builds, so a formatting slip costs a whole cycle.

Run from the workspace root.

```
dart pub get
dart analyze --fatal-infos
dart test packages/onnxruntime_dart
dart test packages/onnxruntime_dart -p chrome   # web-safe subset
python3 .github/scripts/test_matrix.py          # build matrix invariants

cd packages/onnxruntime_dart && dart run ffigen --config ffigen.yaml
```

Tests resolve paths through `test/src/paths.dart`, so they run from the root or
from a package directory.

## Layout

A pub workspace. The submodule and CI are shared, so they sit above the members.

| Path | Contents |
| --- | --- |
| `packages/onnxruntime_dart/` | Core package. |
| `packages/*/lib/src/bindings/*.g.dart` | ffigen output. Never edit. |
| `packages/*/lib/src/backend/` | The FFI and wasm seam. |
| `third_party/onnxruntime` | Pinned submodule. Source of truth for headers and test models. |
| `.github/scripts/ort_matrix.py` | Build matrix. |
| `.agents/` | Agent instructions. `CLAUDE.md` points here. |

Future ecosystem packages (genai, EP plugins, extensions) become workspace
members. Each gets `resolution: workspace` and shares the one submodule.

## Invariants

Generated files end in `.g.dart` and are excluded from analysis and formatting by
pattern. Regenerate, never edit.

Bindings come from the submodule, never a downloaded tarball. `dart run ffigen`
must reproduce the committed output byte for byte.

Version is `X.Y.Z+onnxruntime-<ORT version>`. The suffix matches the submodule
tag. Enforced by `test/version_test.dart`.

Builds are complete: every operator, every opset, all contrib ops, every
platform. `ort_matrix.py` rejects flags that trim the operator set.

Reuse ORT's test corpus rather than authoring models. The submodule ships models
per operator domain, one per element type (`js/node/test/testdata/test_types_*`),
reference input and output pairs, and edge cases such as free dimensions and
fp16. Do not duplicate ORT's own test code: it verifies their kernels compute
correctly, which is their responsibility, not ours.

Tests run against binaries we build, never a published Microsoft release. Theirs
trims opset coverage and is not what we ship, so a green run against it would
prove nothing about ours. The same applies to execution provider libraries as
they are added: build, then test what was built.

Exactly one conditional import, in `lib/src/backend/backend.dart`. Everything
above the seam is shared between native and web.

The seam limits what web can implement, not what the API may declare. A call
WebAssembly cannot support is annotated `@NativeOnly(reason)` and throws through
`unsupportedOnWeb` there, with the same reason in both places. Do not shrink the
API to the intersection of both backends, and never let a web gap be silent or
undocumented.

Execution providers load by path, so users can supply their own. We build two.
Everything else, CUDA and TensorRT and OpenVINO among them, is theirs to
provide, as it is with Microsoft's own distribution.

Shared code imports nothing native. One `dart:ffi` above the backend boundary
breaks the package on the web, and the failure lands in a consumer's build
rather than ours. `test/web_safety_test.dart` enforces it.

Two public libraries. `native.dart` exports the generated C API, so every
`OrtApi` function is reachable by construction rather than by effort.
`onnxruntime_dart.dart` is the ergonomic layer, built on it, covering the common
path. The ergonomic layer is never a ceiling: if something is missing there, it
is reachable in `native.dart`, and reaching for it is expected.

The API is audited against `onnxruntime_c_api.h`, not against the Python
package. Python omits consumer-facing calls we need, `GetEpDevices` and
`BindOutputToDevice` among them, so treating it as the target would inherit its
gaps. Borrow its names where they fit and nothing else.

Every native handle has one owner and one release. `createTensor` borrows its
buffer and does not copy. Public APIs copy in. Anything that outlives its
creating scope gets a `NativeFinalizer`.

Any change to tensor lifetimes must pass the harness in
`test/src/memory_harness.dart`.

`CreateEnv` returns a refcounted process-wide singleton. Never release it: doing
so from one place tears down the environment every other isolate is using, and
the symptom is `Attempt to use DefaultLogger but none has been registered`
followed by a native crash.

Registering an execution provider library mutates process-global state. Doing it
while another thread creates a session crashes the runtime with an alignment
fault rather than failing cleanly, so register before any session exists. Tests
that register are tagged `exclusive`.

The native library reaches Dart as a code asset from `hook/build.dart`, resolved
by `@Native(assetId:)`. Nothing opens it by path except the test helpers that
deliberately exercise an explicit path.

Tests measuring process-global state, such as resident memory, are tagged
`exclusive` and run with concurrency 1. `dart test` runs files concurrently in
one process, so a neighbour allocating is indistinguishable from a leak.

Anything that varies by platform gets a test. ORTCHAR_T width, pointer size,
byte order and shared library naming are all asserted, because the suite runs on
every platform and that is where such assumptions break. Tests needing `dart:io`
or `dart:ffi` carry `@TestOn('vm')`.

## Style

Write like a senior engineer. No filler, no restating the obvious.

Comments explain why, not what, in a line or two. A comment that paraphrases the
code below it is noise. Delete it.

Never cite planning documents, section numbers, or task IDs in committed code.
Those documents are transient and the references rot. Give the reason directly.

No em dashes. No semicolons in prose. Plain sentences.

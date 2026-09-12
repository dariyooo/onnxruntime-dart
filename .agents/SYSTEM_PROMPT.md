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
| `packages/*/tool/src/seam.dart` | The one hand-written link between the two. |
| `third_party/onnxruntime` | Pinned submodule. Source of truth for headers and test models. |
| `.github/scripts/ort_matrix.py` | Build matrix. |
| `.agents/` | Agent instructions. `CLAUDE.md` points here. |

Future ecosystem packages (genai, EP plugins, extensions) become workspace
members. Each gets `resolution: workspace` and shares the one submodule.

## The native and web split

Both backends are generated from pinned headers. Neither is hand-written, and
the same is true of the link between them.

```
onnxruntime_c_api.h        native only, dart:ffi          raw_ffi_calls.g.dart
onnxruntime/wasm/api.h     web only, dart:js_interop      raw_wasm_calls.g.dart
OrtCalls                   the seam both implement        interface.dart
```

`ffi_calls.dart` composes the native side, `wasm_calls.dart` the web side, and
`async_calls.dart` extends the latter for the Asyncify builds, overriding only
the five exports that can suspend.

There were counts here and they were wrong: the C API figure was out by
roughly twenty and the seam figure by one. They came from a header that has
since moved. Counts in a document nothing runs will drift, so the files are
named instead. If you want the numbers, read them off the generated files or
run the generator, which prints them.

Availability is expressed by placement, never by an annotation on a portable
member. An operation in both headers is portable; an operation in one belongs
to that platform. `tool/src/seam.dart` says which is which, and it is the only
file that has to be edited by hand when ONNX Runtime changes.

### When the generator gets it wrong

An update can rename a function, split one into two, or add a capability to one
platform and not the other. `test/seam_table_test.dart` fails with the offending
name rather than letting a backend drift. Four fixes, in order of preference:

1. **A rename.** Change the name in `correspondence`.
2. **A new operation on both sides.** Add an entry naming both. Nothing else.
3. **A new operation on one side.** Add an entry naming only that side. It lands
   on that platform and is invisible to portable code.
4. **A shape the table cannot express**, such as one call becoming two, or a
   platform answering without calling the runtime at all. Set `webDerived` for
   the latter. Otherwise write the method by hand in the backend and list it in
   `handWritten` so the coverage check treats it as deliberate.

Never widen `autoMatched` to make a failure go away. It exists so the table
stays small, and a name that needs a new rule is usually a name that changed
meaning.

`platform_support.g.dart` is generated from the table, and
`test/platform_support_test.dart` checks the WebAssembly backend against it in
both directions: every operation marked unavailable must refuse, and every
operation marked available must not. That is what stops the table becoming a
comment that compiles.

### What the web genuinely cannot do

Not choices. `dlopen` does not exist, so providers and custom operators are
compiled into the build served. `FILESYSTEM=0`, so nothing writes to a path.
Thread count is fixed when the module is instantiated and needs a cross-origin
isolated page to exceed one.

ONNX Runtime compiles the WebGPU and WebNN builds with `ASYNCIFY=1`. There
`asyncInit()` replaces five exports with wrappers that return a promise *or* a
value depending on whether the call suspended, so a synchronous backend would
read a promise as a handle. The loader picks `AsyncWasmCalls` for those builds,
detected by the presence of `asyncInit`.

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

The ONNX Runtime itself is always ours, built from the pinned submodule, never
a published Microsoft release. Theirs trims opset coverage and is not what we
ship, so a green run against it would prove nothing about ours.

That is not true of every component, and the difference matters when reading a
green run. Of the three execution providers, only WebGPU is compiled here. The
CUDA plugin is fetched from upstream's release and the QNN plugin is repackaged
from Qualcomm's wheel, so for those two a passing test says their binary works,
not that ours does. `ep_matrix.py` records which is which. GenAI is mirrored
rather than built for the same reason.

The conditional import that picks a backend is in
`lib/src/backend/calls.dart`. Everything
above the seam is shared between native and web.

The seam limits what web can implement, not what the API may declare. A call
WebAssembly cannot support is annotated `@NativeOnly(reason)` and throws through
`unsupportedOnWeb` there, with the same reason in both places. Do not shrink the
API to the intersection of both backends, and never let a web gap be silent or
undocumented.

Execution providers load by path, so users can supply their own. We package
three: WebGPU, which we build, and CUDA and QNN, which we mirror from upstream.
Everything else, TensorRT and OpenVINO among them, is theirs to provide, as it
is with Microsoft's own distribution.

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

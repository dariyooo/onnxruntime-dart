# Roadmap

What is built, what is next, and the decisions already taken. Kept because the
reasoning behind a plan is the part that gets lost.

## Done

**The base package.** Bindings generated from the pinned ONNX Runtime, an API
over them, binaries built and published for every target, and one CI entry
point that builds and tests. Green on a full build from source, with one
exception recorded in [#1](../../issues/1): `android-arm64` device tests cannot
run on hosted runners.

**ONNX Runtime GenAI.** Token generation on top of a session, generated from
the pinned GenAI submodule the same way, behind a backend boundary so the
package compiles for the web even though upstream publishes no WebAssembly
build. That decision is recorded in [#2](../../issues/2).

**The C API, wrapped.** Every call in the pinned headers is reachable: the
generator covers the shapes it can state as rules, `manual.dart` covers the ones
that need a decision, and `unmapped.txt` says which is which. One call is left,
`GetOpaqueValue`, and the file records why it cannot be wrapped rather than
listing it as work outstanding. GenAI is the same, with two calls held back on
purpose because they are the error plumbing `check()` already owns.

**The example application.** `examples/gallery` runs six upstream models: two
classifiers, an object detector, an LSTM, a sentence transformer and Phi-3 mini
through the GenAI package. Models are fetched from whoever published them, sizes
are shown before they are spent and checked after, and every run reports which
provider actually executed each node rather than which one was asked for.

Two things it does not do yet. Its tests cannot run in CI until
`onnxruntime_genai_binaries` has a release, because the build hook has nothing
to download and a `local_build` override cannot be committed. And the WebGPU
provider is offered only where the build has one.

## Next

### Hosting it on GitHub Pages

Not started. Pages cannot set COOP or COEP headers, and the threaded
WebAssembly builds need cross-origin isolation, so this needs
`coi-serviceworker` or an equivalent. The base package's web tests already run
without those headers on purpose, so the constraint is understood rather than
discovered late.

## Not planned

- **A WebAssembly build of GenAI.** See [#2](../../issues/2). The toolchain is
  already here and no filesystem is needed, but GenAI's own build has no
  emscripten support, and carrying a fork of it is a standing cost for one
  platform.
- **Publishing to pub.dev.** Releases are GitHub only, and are cut by tagging.

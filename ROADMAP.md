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

## Next

### An example application

Not started. It exists to exercise the packages rather than to demonstrate
them, which is why it comes before anything is called finished.

Decided already:

- **Models come from upstream only.** Nothing hand-converted, nothing hosted
  here. A model that needs converting is a model whose behaviour this project
  has to explain rather than ONNX Runtime's.
- **Download size is shown before it is spent.** ResNet50 at 31 MB is fine when
  a reader knows it is 31 MB.
- **A spread rather than one model**: a classifier, an object detector, an
  RNN or LSTM, a small transformer, and something driven by GenAI. Each one
  exercises a different part of the runtime, which is the point.
- **A diagnostic panel**, showing which provider actually ran rather than which
  was asked for. The difference between those two is where most of the
  interesting failures live.

Open, and worth settling before any code: whether this is a Flutter application
reusing the shape of `integration/harness`, or a plain Dart web application.
That decides how much of it can run on Pages at all.

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

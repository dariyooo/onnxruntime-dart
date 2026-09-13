# Building, testing and releasing

How CI works and how a release is made. You do not need any of this to use the
packages, only to work on them.

## Building and testing

There is one workflow with one switch.

By default it builds every binary and then tests what it built, so no binary is
published unless something loaded it first.

Give the `from_release` input a runtime tag, or `latest`, and it skips the
builds and runs the same tests against what is already published. The weekly
scheduled run does this, so a release that stops installing is noticed without
waiting for someone to push.

## Releasing

You release by tagging, one component at a time. The tag says what it releases,
and the pipeline builds only that component:

| tag | releases |
| --- | --- |
| `runtime-v*` | the runtime, base and full |
| `ep-webgpu-v*` | the WebGPU provider |
| `ep-cuda-v*` | the CUDA provider |
| `ep-qnn-v*` | the QNN provider |
| `extensions-v*` | the operator library |
| `genai-v*` | the GenAI library |

The version in the tag is the package's own version, so `runtime-v1.29.0`
releases `onnxruntime_binaries` at `1.29.0`.

This means a provider that gets a new version is released by its own tag, and
nothing else is rebuilt. Pushing to a branch never publishes anything, whichever
branch it is.

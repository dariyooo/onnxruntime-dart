# Building, testing and releasing

How CI works and how a release is cut. You do not need any of this to use the
packages, only to work on them.

## Building and testing

One workflow, with one switch. By default it builds every binary and tests what
it built, so no binary is published without something loading it first. Give the
`from_release` input a runtime tag, or `latest`, and it skips the builds and
runs the same tests against what is already published instead. That is also
what the weekly run does, so a release that stops installing is noticed without
waiting for a push.

## Releasing

Releasing is tagging, one component at a time. The tag names what it releases,
and the pipeline runs that component alone:

| tag | releases |
| --- | --- |
| `runtime-v*` | the runtime, base and full |
| `ep-webgpu-v*` | the WebGPU provider |
| `ep-cuda-v*` | the CUDA provider |
| `ep-qnn-v*` | the QNN provider |
| `extensions-v*` | the operator library |
| `genai-v*` | the GenAI library |

The version in the tag is the package's own, so `runtime-v1.29.0` releases
`onnxruntime_binaries` at `1.29.0`.

So a provider that gains a version is released by its own tag and nothing else
is rebuilt. Pushing to a branch never publishes, whichever branch it is.

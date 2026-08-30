# onnxruntime_dart

Pure-Dart bindings to the [ONNX Runtime](https://onnxruntime.ai) C API. No
Flutter dependency, so it runs in CLI tools and on servers as well as in apps.

## What is different about it

**Complete builds.** Every operator, every opset, all `com.microsoft` contrib
ops, on every platform. The build flags that would trim any of that are rejected
by CI, and a test loads a model from each operator domain against the binary we
ship to prove it.

**The runtime comes with the package.** A build hook resolves the shared library
for the target being built and hands it to Dart as a code asset, verified
against a pinned SHA-256. There is no path to configure and no binary to place.

**Our binaries, not someone else's.** Every library is built from a pinned
ONNX Runtime submodule in our own CI, so a green test run says something about
what we publish.

## Status

Under development. The API above the bindings is not written yet.

| | |
| --- | --- |
| ONNX Runtime | 1.29.0 |
| Platforms building | Linux, macOS, Windows, web |
| Platforms in progress | Android, iOS |

## Versioning

`X.Y.Z+onnxruntime-<version>`. The suffix names the ONNX Runtime release the
package binds, and always matches the pinned submodule.

## License

MIT, as is ONNX Runtime itself. See [LICENSE](LICENSE).

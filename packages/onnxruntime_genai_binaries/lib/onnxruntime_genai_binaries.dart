/// This package ships no Dart API.
///
/// It installs the ONNX Runtime GenAI shared library as a code asset. Use
/// [onnxruntime_genai](https://pub.dev/packages/onnxruntime_genai) for the API.
///
/// It is a package of its own so that an application can choose which GenAI it
/// runs against without waiting for the API package to be released for it.
///
/// The library is not self contained. It looks up `OrtGetApiBase` in an ONNX
/// Runtime that is already loaded rather than linking against one, which is why
/// `onnxruntime_binaries` is a dependency here and both are installed together.
library;

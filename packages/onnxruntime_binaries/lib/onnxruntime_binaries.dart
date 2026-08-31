/// This package ships no Dart API.
///
/// It installs the ONNX Runtime shared library as a code asset. Use
/// [onnxruntime_dart](https://pub.dev/packages/onnxruntime_dart) for the API.
///
/// Two libraries are published and this installs one of them. The default has
/// every operator and every execution provider we build, which is what almost
/// every application wants. On-device training has to be compiled in, so it is
/// a second library rather than something loadable:
///
/// ```yaml
/// hooks:
///   user_defines:
///     onnxruntime_binaries:
///       variant: full
/// ```
///
/// `trainingIsAvailable()` reports which one you got.
library;

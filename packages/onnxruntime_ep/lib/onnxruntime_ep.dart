/// This package ships no Dart API.
///
/// It installs the execution provider libraries named in `user_defines`:
///
/// ```yaml
/// hooks:
///   user_defines:
///     onnxruntime_ep:
///       providers: [cuda, webgpu]
/// ```
///
/// Registering them is `registerBundledProviders()` in
/// [onnxruntime_dart](https://pub.dev/packages/onnxruntime_dart).
library;

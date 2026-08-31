/// This package ships no Dart API.
///
/// It installs the qnn execution provider library, and the Qualcomm AI Runtime
/// it loads beside itself. Register it with `registerBundledProviders`, from
/// [onnxruntime_dart](https://pub.dev/packages/onnxruntime_dart), which finds
/// every provider package the application depends on.
///
/// Windows and Linux only. On Android QNN is linked into a whole runtime
/// rather than published as a plugin, so it cannot layer on ours.
library;

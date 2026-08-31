/// This package ships no Dart API.
///
/// It installs the onnxruntime-extensions operator library. Pass its path to a
/// session with `SessionOptions(customOpsLibraries: [extensionsLibraryPath()!])`,
/// from `package:onnxruntime_dart/native.dart`, which finds it wherever the
/// bundle put it.
library;

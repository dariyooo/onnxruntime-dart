/// Support for the packages that ship the ONNX Runtime binaries.
///
/// `onnxruntime_base` and `onnxruntime_full` are the same build hook
/// with a different variant, so the hook itself lives here and each of them is
/// a few lines naming which library it installs. Nothing in the ordinary API
/// needs this library.
library;

export 'src/install.dart' show installProviders, installRuntime;
export 'src/target.dart'
    show
        OrtProvider,
        OrtVariant,
        UnsupportedTarget,
        assetFileName,
        assetUrl,
        libraryFileName,
        supportedTargets,
        targetId;

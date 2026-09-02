/// Support for the packages that ship the ONNX Runtime binaries.
///
/// The runtime, the providers and the extensions library all install the same
/// way: resolve a target, take a local build if one was configured, otherwise
/// download and cache a release asset. That work lives here, and each package
/// is a few lines naming what it installs. Nothing in the ordinary API
/// needs this library.
library;

export 'src/install.dart'
    show installExtensions, installProvider, installRuntime;
export 'src/target.dart'
    show
        OrtExtensions,
        OrtProvider,
        OrtVariant,
        UnsupportedTarget,
        assetFileName,
        assetUrl,
        extensionsAssetFileName,
        providerAssetFileName,
        extensionsAssetUrl,
        libraryFileName,
        supportedTargets,
        targetId;

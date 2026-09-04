/// The operator library on the web, where there is none to point at.
///
/// Custom operators reach ONNX Runtime one of two ways, and neither produces a
/// path here.
///
/// Natively they are a shared library, opened at run time. The WebAssembly
/// build has no loader for one, because it is not built with Emscripten's
/// dynamic linking. That is a build decision rather than something the
/// platform forbids, but it is settled from a consumer's side either way.
///
/// The other way is to compile them in, which is what a web build has to do.
/// ONNX Runtime takes `--use_extensions` for that and puts no WebAssembly
/// guard on it, so a variant carrying these operators is buildable. The builds
/// published here are not: they carry XNNPACK, WebGPU and WebNN. So the honest
/// answer is not that extensions are impossible on the web, it is that they
/// would have to be inside the runtime rather than beside it, and the runtime
/// being served does not have them.
///
/// This half exists so that importing the package does not break a web build.
/// An application that uses the extensions on native and something else on the
/// web can depend on it, ask, and be told there is nothing here, rather than
/// failing to compile.
library;

/// Null, always: nothing was installed as a file.
///
/// A caller passing this to `SessionOptions.customOpsLibraries` should skip it
/// when it is null rather than assert on it, which is the same thing it should
/// do on a native platform where the package was not installed.
String? extensionsPath() => null;

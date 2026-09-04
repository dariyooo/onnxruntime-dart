/// The operator library on the web, where there is none to point at.
///
/// Custom operators reach ONNX Runtime as a shared library, and the
/// WebAssembly build has no loader for one: an operator that is not compiled
/// into the runtime being served cannot be added to it. So there is no path to
/// report and null is the whole answer.
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

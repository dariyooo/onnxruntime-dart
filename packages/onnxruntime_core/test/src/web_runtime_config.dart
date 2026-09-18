/// Where a browser run can fetch the WebAssembly runtime.
///
/// Empty here on purpose, so `dart test -p chrome` on a fresh checkout skips
/// the runtime tests rather than failing on a file it has no way to have. CI
/// overwrites this after unpacking the build from the same run, and
/// `tool/fetch_web_runtime.sh` does the same locally.
///
/// A file rather than an environment variable because `dart test` has no way
/// to pass a compile-time define through to the browser compiler.
library;

const webRuntimeLoader = '';
const webRuntimeWasm = '';

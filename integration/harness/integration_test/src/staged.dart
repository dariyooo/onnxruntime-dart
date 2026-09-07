/// What this ABI was given, as CI staged it.
///
/// Not every layer exists for every Android ABI. The WebGPU provider leaves
/// the 32-bit ones out deliberately, and upstream's GenAI archive carries only
/// the 64-bit ones. A test that skipped itself there would report the same
/// green as one that ran, so the job states what it staged and the tests
/// assert in both directions: present and loading, or absent and admitting it.
///
/// Defaults are true so a local `flutter test` without the defines behaves as
/// the fully equipped case rather than quietly checking nothing.
library;

const hasWebGpu = bool.fromEnvironment('HAS_WEBGPU', defaultValue: true);
const hasGenAi = bool.fromEnvironment('HAS_GENAI', defaultValue: true);

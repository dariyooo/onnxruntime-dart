/// What this provider is called, in the two places it has to agree.
///
/// Imports nothing, so both halves of the seam can name it.
library;

/// The library's file name without prefix or extension.
const providerLibraryStem = 'onnxruntime_providers_webgpu';

/// The name ONNX Runtime knows the provider by.
const providerName = 'webgpu';

/// The oldest ONNX Runtime this provider works against.
const minimumRuntime = '1.24.4';

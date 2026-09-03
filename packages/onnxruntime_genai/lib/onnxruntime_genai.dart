/// Generative AI on top of ONNX Runtime: token generation, KV caching and
/// sampling, driven by ONNX Runtime GenAI.
///
/// The library is installed by
/// [onnxruntime_genai_binaries](https://pub.dev/packages/onnxruntime_genai_binaries),
/// which is a separate package so that an application can choose which build it
/// runs against, or take none and supply one itself. Without it the first call
/// finds no symbols.
///
/// GenAI does not link ONNX Runtime. It looks up `OrtGetApiBase` in a runtime
/// that is already loaded, so `onnxruntime_binaries` has to be installed too,
/// which is why the binaries package depends on it.
///
/// ```dart
/// final model = Model('path/to/model');
/// final tokenizer = Tokenizer(model);
/// ```
///
/// Every handle is released explicitly, as in the base package. A finalizer
/// does not run in time to matter and cannot be relied on to run at all.
library;

export 'src/api/api.dart';

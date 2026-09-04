// AUTO GENERATED FILE, DO NOT EDIT.
//
// Generated from third_party/onnxruntime-genai/src/ort_genai_c.h.
// Regenerate with `dart run tool/generate_bindings.dart` from this package.

/// The generated classes over the GenAI API.
///
/// One library rather than one per type, because they construct each other and
/// a private constructor is private to its library.
library;

import 'dart:typed_data';

import '../backend/calls.dart';
import '../backend/interface.dart';
import '../backend/types.dart';

export '../backend/types.dart'
    show GenAiException, GenAiHandle, GenAiPtr, GenAiUnsupported;

part 'adapters.g.dart';
part 'audios.g.dart';
part 'config.g.dart';
part 'engine.g.dart';
part 'genai.g.dart';
part 'generator.g.dart';
part 'generator_params.g.dart';
part 'images.g.dart';
part 'model.g.dart';
part 'multi_modal_processor.g.dart';
part 'named_tensors.g.dart';
part 'request.g.dart';
part 'runtime_settings.g.dart';
part 'sequences.g.dart';
part 'streaming_processor.g.dart';
part 'string_array.g.dart';
part 'tensor.g.dart';
part 'tokenizer.g.dart';
part 'tokenizer_stream.g.dart';

/// The backend for this platform, made once.
final GenAiCalls _calls = createCalls();

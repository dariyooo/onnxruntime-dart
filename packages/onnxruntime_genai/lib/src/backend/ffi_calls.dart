/// The native backend: the generated calls, and anywhere they are not enough.
///
/// Hand-written on purpose, and almost empty on purpose. Everything GenAI's
/// header declares is generated into [GeneratedFfiCalls] and mixed in below, so
/// this file holds nothing at all until a call needs a decision no generator
/// can make: a value to validate before it is passed, a buffer whose lifetime
/// the signature cannot state, or several calls that have to happen together.
///
/// Overriding one here replaces the generated version, and the compiler checks
/// the two agree. That is the point of the split: the generated file stays
/// regenerable and nobody has to edit a file that says DO NOT EDIT.
library;

import 'ffi_generated.g.dart';
import 'interface.dart';

/// The backend for this platform.
GenAiCalls createCalls() => FfiGenAiCalls();

/// GenAI reached through `dart:ffi`.
///
/// No overrides yet. `OgaCreateTensorFromBuffer` is the one to watch: it keeps
/// the buffer it is given rather than copying it, and if that ever needs
/// enforcing rather than documenting, it is enforced here.
final class FfiGenAiCalls with GeneratedFfiCalls implements GenAiCalls {}

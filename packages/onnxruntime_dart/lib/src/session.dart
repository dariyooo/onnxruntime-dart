/// A loaded model.
library;

import 'dart:typed_data';

import 'backend/ffi_calls.dart';
import 'backend/types.dart';
import 'handle.dart';

/// A model, loaded and ready to run.
///
/// Owns its native handle. [dispose] frees it, and a dropped reference frees it
/// too, so forgetting costs a delay rather than a leak. Belongs to the isolate
/// that created it: build one where it is used rather than passing it across.
final class Session {
  Session._(this._calls, this._handle, this.inputs, this.outputs);

  /// Loads a model from bytes.
  ///
  /// Only from bytes. Loading by path would mean `ORTCHAR_T`, which is UTF-16
  /// on Windows, for no gain over reading the file first.
  factory Session.fromBytes(List<int> model, {SessionOptions? options}) {
    final calls = FfiCalls.instance();
    final bytes = model is Uint8List ? model : Uint8List.fromList(model);

    final optionsHandle = calls.createSessionOptions();
    try {
      for (final entry
          in (options?.config ?? const <String, String>{}).entries) {
        calls.addSessionConfigEntry(optionsHandle, entry.key, entry.value);
      }

      final session = calls.createSession(bytes, optionsHandle);
      final handle = OrtHandle(session, calls.releaseSession, 'Session');

      final (inputs, outputs) = calls.inputOutputCount(session);
      return Session._(
        calls,
        handle,
        List.unmodifiable([
          for (var i = 0; i < inputs; i++)
            calls.inputOutputMetadata(session, i, input: true),
        ]),
        List.unmodifiable([
          for (var i = 0; i < outputs; i++)
            calls.inputOutputMetadata(session, i, input: false),
        ]),
      );
    } finally {
      // Session options are copied into the session, so they are only needed
      // for the call itself.
      calls.releaseSessionOptions(optionsHandle);
    }
  }

  // ignore: unused_field
  final FfiCalls _calls;
  final OrtHandle _handle;

  /// What the model takes, in the order the runtime reports.
  final List<OrtTensorMeta> inputs;

  /// What the model produces.
  final List<OrtTensorMeta> outputs;

  bool get isDisposed => _handle.isReleased;

  /// Frees the model now rather than waiting for collection.
  void dispose() => _handle.release();

  @override
  String toString() => 'Session(${inputs.length} in, ${outputs.length} out)'
      '${isDisposed ? ' disposed' : ''}';
}

/// How a session is configured.
///
/// Most of ONNX Runtime's options are string configuration entries, and on the
/// web they are the only mechanism, so [config] is the general form.
///
/// Use the generated `SessionConfig` keys. ONNX Runtime does not validate them:
/// a misspelled key is accepted and silently ignored, so the option never takes
/// effect and nothing says why.
final class SessionOptions {
  const SessionOptions({this.config = const {}});

  final Map<String, String> config;
}

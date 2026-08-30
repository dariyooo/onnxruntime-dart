/// Ownership for the handles ONNX Runtime hands back.
///
/// Every `Create*` in the C API has a matching `Release*`, and Dart has no
/// destructor to call it. One mechanism covers all of them, because the backend
/// boundary already exposes each `release*` and `Finalizer` is `dart:core`, so
/// this compiles for the web as well as for native.
///
/// A dropped reference frees rather than leaks, and a forgotten [release] costs
/// a delay rather than a leak.
library;

import 'backend/types.dart';

/// What the finalizer needs after the handle itself is unreachable.
///
/// Deliberately not holding the [OrtHandle]: a finalizer that captures its own
/// owner keeps it alive and never runs.
final class _Pending {
  _Pending(this.pointer, this.release);

  final OrtPtr pointer;
  final void Function(OrtPtr) release;
}

final Finalizer<_Pending> _finalizer = Finalizer(
  (pending) => pending.release(pending.pointer),
);

/// A handle with exactly one owner and exactly one release.
///
/// Releasing twice throws rather than double-freeing, and using a released
/// handle throws rather than reading freed memory. Both otherwise corrupt the
/// heap and surface somewhere unrelated.
final class OrtHandle {
  /// Takes ownership of [pointer], to be freed by [release].
  ///
  /// [typeName] appears in errors, so it should name what this is, such as
  /// `OrtSession`.
  OrtHandle(OrtPtr pointer, void Function(OrtPtr) release, String typeName)
      : _pointer = pointer,
        _release = release,
        _typeName = typeName {
    if (pointer.isNull) {
      throw ArgumentError.value(pointer, 'pointer', 'cannot own a null handle');
    }
    _finalizer.attach(this, _Pending(pointer, release), detach: this);
  }

  OrtPtr _pointer;
  final void Function(OrtPtr) _release;
  final String _typeName;
  var _released = false;

  /// The handle, while it is alive.
  OrtPtr get pointer {
    if (_released) {
      throw StateError('this $_typeName was released and cannot be used again');
    }
    return _pointer;
  }

  bool get isReleased => _released;

  /// Frees now rather than waiting for collection.
  ///
  /// Not idempotent, deliberately. A second release means two pieces of code
  /// believe they own this, which is worth failing on rather than hiding.
  void release() {
    if (_released) {
      throw StateError('this $_typeName was already released');
    }
    _released = true;
    _finalizer.detach(this);
    _release(_pointer);
    _pointer = OrtPtr.nullPtr;
  }

  @override
  String toString() => _released
      ? '$_typeName(released)'
      : '$_typeName(0x${_pointer.address.toRadixString(16)})';
}

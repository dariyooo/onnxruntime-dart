/// Where a loaded library actually is on disk.
///
/// Dart bundles a code asset and loads it for us, but never says where it put
/// it, and the answer differs per platform: `bundle/lib` for `dart build cli`,
/// `.dart_tool/lib` under `dart run`, `jniLibs` inside an APK, a code-signed
/// framework in an iOS app. ONNX Runtime needs a path, because
/// `RegisterExecutionProviderLibrary` takes one and opens it itself.
///
/// So rather than predicting the layout, ask the loader. Given the address of
/// any symbol, the operating system knows which file it came from: `dladdr`
/// everywhere POSIX, `GetModuleHandleEx` plus `GetModuleFileName` on Windows.
/// That works wherever the asset ended up, including places no layout rule
/// would have guessed.
library;

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// `Dl_info` from `<dlfcn.h>`.
final class _DlInfo extends Struct {
  /// Path of the file the address came from.
  external Pointer<Utf8> fileName;
  external Pointer<Void> fileBase;
  external Pointer<Utf8> symbolName;
  external Pointer<Void> symbolAddress;
}

typedef _DladdrNative = Int32 Function(Pointer<Void>, Pointer<_DlInfo>);
typedef _Dladdr = int Function(Pointer<Void>, Pointer<_DlInfo>);

typedef _GetModuleHandleExNative = Int32 Function(
    Uint32, Pointer<Utf16>, Pointer<IntPtr>);
typedef _GetModuleHandleEx = int Function(int, Pointer<Utf16>, Pointer<IntPtr>);

typedef _GetModuleFileNameNative = Uint32 Function(
    IntPtr, Pointer<Utf16>, Uint32);
typedef _GetModuleFileName = int Function(int, Pointer<Utf16>, int);

/// Take the address as given, and do not bump the module's reference count.
const _fromAddress = 0x00000004;
const _unchangedRefcount = 0x00000002;

/// The file containing [address], or null if the loader does not know.
///
/// [address] must point inside a loaded library, such as a function in it.
String? libraryPathOf(Pointer<Void> address) =>
    Platform.isWindows ? _windowsPath(address) : _posixPath(address);

String? _posixPath(Pointer<Void> address) {
  final dladdr =
      DynamicLibrary.process().lookupFunction<_DladdrNative, _Dladdr>('dladdr');
  final info = calloc<_DlInfo>();
  try {
    // dladdr returns non-zero on success, unlike most of POSIX.
    if (dladdr(address, info) == 0) return null;
    if (info.ref.fileName == nullptr) return null;
    return info.ref.fileName.toDartString();
  } finally {
    calloc.free(info);
  }
}

String? _windowsPath(Pointer<Void> address) {
  final kernel32 = DynamicLibrary.open('kernel32.dll');
  final getModuleHandleEx =
      kernel32.lookupFunction<_GetModuleHandleExNative, _GetModuleHandleEx>(
          'GetModuleHandleExW');
  final getModuleFileName =
      kernel32.lookupFunction<_GetModuleFileNameNative, _GetModuleFileName>(
          'GetModuleFileNameW');

  final module = calloc<IntPtr>();
  // MAX_PATH is not the limit for a long path, so allow well beyond it.
  const length = 32768;
  final buffer = calloc<Uint16>(length).cast<Utf16>();
  try {
    final found = getModuleHandleEx(
      _fromAddress | _unchangedRefcount,
      address.cast<Utf16>(),
      module,
    );
    if (found == 0) return null;

    final written = getModuleFileName(module.value, buffer, length);
    if (written == 0 || written >= length) return null;
    return buffer.toDartString();
  } finally {
    calloc
      ..free(module)
      ..free(buffer);
  }
}

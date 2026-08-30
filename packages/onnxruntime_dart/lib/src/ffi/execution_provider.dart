/// Loading execution provider plugins at runtime.
///
/// A plugin is a shared library exporting `CreateEpFactories`. ONNX Runtime
/// opens it itself given a path, so the only work here is marshalling that path
/// and reporting failures. Providers compiled into the core library need none
/// of this.
///
/// The path is `ORTCHAR_T`, which is UTF-16 on Windows, so it goes through
/// [allocateOrtPath] rather than being written as UTF-8.
library;

import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../bindings/ort_bindings.g.dart';
import 'ort_path.dart';
import 'status.dart';

/// Registers the plugin at [path] under [name].
///
/// [name] identifies the library for [unregisterExecutionProviderLibrary] and
/// is not the provider's own name. Throws [OrtException] if the library is
/// missing, is not a plugin, or was built against a different ONNX Runtime.
void registerExecutionProviderLibrary(
  OrtApi api,
  Pointer<OrtEnv> env, {
  required String name,
  required String path,
}) {
  final arena = Arena();
  try {
    checkStatus(
      api,
      api.RegisterExecutionProviderLibrary.asFunction<
          Pointer<OrtStatus> Function(
            Pointer<OrtEnv>,
            Pointer<Char>,
            Pointer<Char>,
          )>()(
        env,
        name.toNativeUtf8(allocator: arena).cast(),
        allocateOrtPath(path, arena),
      ),
    );
  } finally {
    arena.releaseAll();
  }
}

/// Unregisters the plugin previously registered as [name].
void unregisterExecutionProviderLibrary(
  OrtApi api,
  Pointer<OrtEnv> env, {
  required String name,
}) {
  final arena = Arena();
  try {
    checkStatus(
      api,
      api.UnregisterExecutionProviderLibrary.asFunction<
          Pointer<OrtStatus> Function(Pointer<OrtEnv>, Pointer<Char>)>()(
        env,
        name.toNativeUtf8(allocator: arena).cast(),
      ),
    );
  } finally {
    arena.releaseAll();
  }
}

/// Number of execution provider devices the environment can see.
///
/// Registering a plugin adds its devices, so this rising after a registration
/// is what proves the plugin actually loaded.
int executionProviderDeviceCount(OrtApi api, Pointer<OrtEnv> env) {
  final arena = Arena();
  try {
    final devices = arena<Pointer<Pointer<OrtEpDevice>>>();
    final count = arena<Size>();
    checkStatus(
      api,
      api.GetEpDevices.asFunction<
          Pointer<OrtStatus> Function(
            Pointer<OrtEnv>,
            Pointer<Pointer<Pointer<OrtEpDevice>>>,
            Pointer<Size>,
          )>()(env, devices, count),
    );
    return count.value;
  } finally {
    arena.releaseAll();
  }
}

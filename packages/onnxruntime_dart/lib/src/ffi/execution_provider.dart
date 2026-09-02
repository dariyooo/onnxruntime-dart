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
///
/// Available to every session created after this returns. ONNX Runtime places
/// no ordering constraint on registration, so a provider obtained at run time
/// can be registered then; sessions already built keep what they were built
/// with.
///
/// Do not race it against session creation on another thread. It mutates the
/// environment, and doing so has been seen to crash the runtime with an
/// alignment fault rather than failing cleanly.
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
///
/// Release every session using it first. This is the ordering ONNX Runtime
/// actually requires, and the one people expect on the other call: unloading
/// the library while a session still holds providers created from it leaves
/// that session pointing into unmapped memory.
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

/// The devices a registered provider contributed, by the name it was
/// registered under.
///
/// A plugin's devices are how a session selects it. Empty when the name is not
/// a registered plugin, which is the case for every provider compiled into the
/// runtime.
List<Pointer<OrtEpDevice>> executionProviderDevices(
  OrtApi api,
  Pointer<OrtEnv> env,
  String name,
) {
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

    final epName = api.EpDevice_EpName.asFunction<
        Pointer<Char> Function(Pointer<OrtEpDevice>)>();

    return [
      for (var i = 0; i < count.value; i++)
        if (_sameProvider(
          epName(devices.value[i]).cast<Utf8>().toDartString(),
          name,
        ))
          devices.value[i],
    ];
  } finally {
    arena.releaseAll();
  }
}

/// The provider name of every device the environment can see.
///
/// For saying what was there when the one being asked for was not. A provider
/// that registered but contributed no device looks identical to one that was
/// never registered, and the two want different answers.
List<String> executionProviderDeviceNames(OrtApi api, Pointer<OrtEnv> env) {
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

    final epName = api.EpDevice_EpName.asFunction<
        Pointer<Char> Function(Pointer<OrtEpDevice>)>();

    return [
      for (var i = 0; i < count.value; i++)
        epName(devices.value[i]).cast<Utf8>().toDartString(),
    ];
  } finally {
    arena.releaseAll();
  }
}

/// Selects a registered plugin provider for a session.
///
/// The by-name call resolves against the providers compiled into the runtime
/// and knows nothing about a plugin, so a plugin is selected by handing over
/// the devices it contributed instead.
void appendExecutionProviderDevices(
  OrtApi api,
  Pointer<OrtSessionOptions> options,
  Pointer<OrtEnv> env,
  List<Pointer<OrtEpDevice>> devices,
  Map<String, String> configuration,
) {
  final arena = Arena();
  try {
    final list = arena<Pointer<OrtEpDevice>>(devices.length);
    for (var i = 0; i < devices.length; i++) {
      list[i] = devices[i];
    }

    final keys = arena<Pointer<Char>>(configuration.length);
    final values = arena<Pointer<Char>>(configuration.length);
    var i = 0;
    for (final entry in configuration.entries) {
      keys[i] = entry.key.toNativeUtf8(allocator: arena).cast();
      values[i] = entry.value.toNativeUtf8(allocator: arena).cast();
      i++;
    }

    checkStatus(
      api,
      api.SessionOptionsAppendExecutionProvider_V2.asFunction<
          Pointer<OrtStatus> Function(
            Pointer<OrtSessionOptions>,
            Pointer<OrtEnv>,
            Pointer<Pointer<OrtEpDevice>>,
            int,
            Pointer<Pointer<Char>>,
            Pointer<Pointer<Char>>,
            int,
          )>()(
        options,
        env,
        list,
        devices.length,
        keys,
        values,
        configuration.length,
      ),
    );
  } finally {
    arena.releaseAll();
  }
}

/// Whether two provider names mean the same provider.
///
/// A plugin's devices carry the provider's own name, `WebGpuExecutionProvider`,
/// while the name it was registered under is whatever the caller chose, and
/// what an application writes is usually the short form. ONNX Runtime accepts
/// both spellings for the providers built into it, so the same is accepted
/// here.
bool _sameProvider(String a, String b) => _shortName(a) == _shortName(b);

String _shortName(String name) {
  final lower = name.toLowerCase();
  return lower.endsWith('executionprovider')
      ? lower.substring(0, lower.length - 'executionprovider'.length)
      : lower;
}

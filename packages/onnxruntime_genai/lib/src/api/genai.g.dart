// AUTO GENERATED FILE, DO NOT EDIT.
//
// Generated from third_party/onnxruntime-genai/src/ort_genai_c.h.
// Regenerate with `dart run tool/generate_bindings.dart` from this package.
//
// The functions that belong to no handle: logging, telemetry, the process wide
// device selection, and provider registration.

part of 'api.dart';

/// Wraps `OgaShutdown`.
void shutdown() => OgaShutdown();

/// Wraps `OgaSetTelemetryEnabled`.
void setTelemetryEnabled(bool enabled) => withArena((arena) => OgaSetTelemetryEnabled(enabled));

/// Wraps `OgaSetLogBool`.
void setLogBool(String name, bool value) => withArena((arena) {
      check(OgaSetLogBool(cString(arena, name), value));
    });

/// Wraps `OgaSetLogString`.
void setLogString(String name, String value) => withArena((arena) {
      check(OgaSetLogString(cString(arena, name), cString(arena, value)));
    });

/// Wraps `OgaDestroyString`.
void destroyString(String value) => withArena((arena) => OgaDestroyString(cString(arena, value)));

/// Wraps `OgaRegisterExecutionProviderLibrary`.
void registerExecutionProviderLibrary(String registrationName, String libraryPath) => withArena((arena) => OgaRegisterExecutionProviderLibrary(cString(arena, registrationName), cString(arena, libraryPath)));

/// Wraps `OgaUnregisterExecutionProviderLibrary`.
void unregisterExecutionProviderLibrary(String registrationName) => withArena((arena) => OgaUnregisterExecutionProviderLibrary(cString(arena, registrationName)));


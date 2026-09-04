// AUTO GENERATED FILE, DO NOT EDIT.
//
// Generated from third_party/onnxruntime-genai/src/ort_genai_c.h.
// Regenerate with `dart run tool/generate_bindings.dart` from this package.
//
// The functions that belong to no handle: logging, telemetry, the process wide
// device selection, and provider registration.

part of 'api.dart';

/// Wraps `OgaShutdown`.
void shutdown() => _calls.shutdown();

/// Wraps `OgaSetTelemetryEnabled`.
void setTelemetryEnabled(bool enabled) => _calls.setTelemetryEnabled(enabled);

/// Wraps `OgaSetLogBool`.
void setLogBool(String name, bool value) => _calls.setLogBool(name, value);

/// Wraps `OgaSetLogString`.
void setLogString(String name, String value) =>
    _calls.setLogString(name, value);

/// Wraps `OgaSetLogCallback`.
void setLogCallback(GenAiPtr callback) => _calls.setLogCallback(callback);

/// Wraps `OgaDestroyString`.
void destroyString(String value) => _calls.destroyString(value);

/// Wraps `OgaSetCurrentGpuDeviceId`.
void setCurrentGpuDeviceId(int deviceId) =>
    _calls.setCurrentGpuDeviceId(deviceId);

/// Wraps `OgaGetCurrentGpuDeviceId`.
int getCurrentGpuDeviceId() => _calls.getCurrentGpuDeviceId();

/// Wraps `OgaRegisterExecutionProviderLibrary`.
void registerExecutionProviderLibrary(
        String registrationName, String libraryPath) =>
    _calls.registerExecutionProviderLibrary(registrationName, libraryPath);

/// Wraps `OgaUnregisterExecutionProviderLibrary`.
void unregisterExecutionProviderLibrary(String registrationName) =>
    _calls.unregisterExecutionProviderLibrary(registrationName);

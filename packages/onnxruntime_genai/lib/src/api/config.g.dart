// AUTO GENERATED FILE, DO NOT EDIT.
//
// Generated from third_party/onnxruntime-genai/src/ort_genai_c.h.
// Regenerate with `dart run tool/generate_bindings.dart` from this package.

part of 'api.dart';

/// Wraps the `OgaConfig` handle.
///
/// Above the backend boundary, so it names no pointer type and forwards
/// everything to whichever backend was selected for this platform.
final class Config extends GenAiHandle {
  Config._(super.handle);

  @override
  void destroy(GenAiPtr handle) => _calls.destroyConfig(handle);

  /// Wraps `OgaCreateConfig`.
  factory Config(String configPath) =>
      Config._(_calls.createConfig(configPath));

  /// Wraps `OgaCreateConfigFromPackageEp`.
  factory Config.fromPackageEp(String configPath, String ep) =>
      Config._(_calls.createConfigFromPackageEp(configPath, ep));

  /// Wraps `OgaConfigClearProviders`.
  void clearProviders() => _calls.configClearProviders(handle);

  /// Wraps `OgaConfigAppendProvider`.
  void appendProvider(String provider) => _calls.configAppendProvider(handle, provider);

  /// Wraps `OgaConfigSetProviderOption`.
  void setProviderOption(String provider, String key, String value) => _calls.configSetProviderOption(handle, provider, key, value);

  /// Wraps `OgaConfigAddModelData`.
  void addModelData(String modelFilename, Uint8List modelData) => _calls.configAddModelData(handle, modelFilename, modelData);

  /// Wraps `OgaConfigRemoveModelData`.
  void removeModelData(String modelFilename) => _calls.configRemoveModelData(handle, modelFilename);

  /// Wraps `OgaConfigSetDecoderProviderOptionsHardwareDeviceType`.
  void setDecoderProviderOptionsHardwareDeviceType(String provider, String hardwareDeviceType) => _calls.configSetDecoderProviderOptionsHardwareDeviceType(handle, provider, hardwareDeviceType);

  /// Wraps `OgaConfigSetDecoderProviderOptionsHardwareDeviceId`.
  void setDecoderProviderOptionsHardwareDeviceId(String provider, int hardwareDeviceId) => _calls.configSetDecoderProviderOptionsHardwareDeviceId(handle, provider, hardwareDeviceId);

  /// Wraps `OgaConfigSetDecoderProviderOptionsHardwareVendorId`.
  void setDecoderProviderOptionsHardwareVendorId(String provider, int hardwareVendorId) => _calls.configSetDecoderProviderOptionsHardwareVendorId(handle, provider, hardwareVendorId);

  /// Wraps `OgaConfigClearDecoderProviderOptionsHardwareDeviceType`.
  void clearDecoderProviderOptionsHardwareDeviceType(String provider) => _calls.configClearDecoderProviderOptionsHardwareDeviceType(handle, provider);

  /// Wraps `OgaConfigClearDecoderProviderOptionsHardwareDeviceId`.
  void clearDecoderProviderOptionsHardwareDeviceId(String provider) => _calls.configClearDecoderProviderOptionsHardwareDeviceId(handle, provider);

  /// Wraps `OgaConfigClearDecoderProviderOptionsHardwareVendorId`.
  void clearDecoderProviderOptionsHardwareVendorId(String provider) => _calls.configClearDecoderProviderOptionsHardwareVendorId(handle, provider);

  /// Wraps `OgaConfigOverlay`.
  void overlay(String json) => _calls.configOverlay(handle, json);

  /// Wraps `OgaCreateModelFromConfig`.
  Model createModelFromConfig() =>
      Model._(_calls.createModelFromConfig(handle));

}

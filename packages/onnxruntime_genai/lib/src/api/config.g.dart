// AUTO GENERATED FILE, DO NOT EDIT.
//
// Generated from third_party/onnxruntime-genai/src/ort_genai_c.h.
// Regenerate with `dart run tool/generate_bindings.dart` from this package.

part of 'api.dart';

/// Wraps the `OgaConfig` handle.
final class Config extends GenAiHandle<OgaConfig> {
  Config._(super.handle);

  @override
  void destroy(Pointer<OgaConfig> handle) => OgaDestroyConfig(handle);

  /// Wraps `OgaCreateConfig`.
  factory Config(String configPath) => withArena((arena) {
        final out = arena<Pointer<OgaConfig>>();
        check(OgaCreateConfig(cString(arena, configPath), out));
        return Config._(out.value);
      });

  /// Wraps `OgaCreateConfigFromPackageEp`.
  factory Config.fromPackageEp(String configPath, String ep) => withArena((arena) {
        final out = arena<Pointer<OgaConfig>>();
        check(OgaCreateConfigFromPackageEp(cString(arena, configPath), cString(arena, ep), out));
        return Config._(out.value);
      });

  /// Wraps `OgaConfigClearProviders`.
  void clearProviders() => withArena((arena) {
        check(OgaConfigClearProviders(handle));
      });

  /// Wraps `OgaConfigAppendProvider`.
  void appendProvider(String provider) => withArena((arena) {
        check(OgaConfigAppendProvider(handle, cString(arena, provider)));
      });

  /// Wraps `OgaConfigSetProviderOption`.
  void setProviderOption(String provider, String key, String value) => withArena((arena) {
        check(OgaConfigSetProviderOption(handle, cString(arena, provider), cString(arena, key), cString(arena, value)));
      });

  /// Wraps `OgaConfigRemoveModelData`.
  void removeModelData(String modelFilename) => withArena((arena) {
        check(OgaConfigRemoveModelData(handle, cString(arena, modelFilename)));
      });

  /// Wraps `OgaConfigSetDecoderProviderOptionsHardwareDeviceType`.
  void setDecoderProviderOptionsHardwareDeviceType(String provider, String hardwareDeviceType) => withArena((arena) {
        check(OgaConfigSetDecoderProviderOptionsHardwareDeviceType(handle, cString(arena, provider), cString(arena, hardwareDeviceType)));
      });

  /// Wraps `OgaConfigSetDecoderProviderOptionsHardwareDeviceId`.
  void setDecoderProviderOptionsHardwareDeviceId(String provider, int hardwareDeviceId) => withArena((arena) {
        check(OgaConfigSetDecoderProviderOptionsHardwareDeviceId(handle, cString(arena, provider), hardwareDeviceId));
      });

  /// Wraps `OgaConfigSetDecoderProviderOptionsHardwareVendorId`.
  void setDecoderProviderOptionsHardwareVendorId(String provider, int hardwareVendorId) => withArena((arena) {
        check(OgaConfigSetDecoderProviderOptionsHardwareVendorId(handle, cString(arena, provider), hardwareVendorId));
      });

  /// Wraps `OgaConfigClearDecoderProviderOptionsHardwareDeviceType`.
  void clearDecoderProviderOptionsHardwareDeviceType(String provider) => withArena((arena) {
        check(OgaConfigClearDecoderProviderOptionsHardwareDeviceType(handle, cString(arena, provider)));
      });

  /// Wraps `OgaConfigClearDecoderProviderOptionsHardwareDeviceId`.
  void clearDecoderProviderOptionsHardwareDeviceId(String provider) => withArena((arena) {
        check(OgaConfigClearDecoderProviderOptionsHardwareDeviceId(handle, cString(arena, provider)));
      });

  /// Wraps `OgaConfigClearDecoderProviderOptionsHardwareVendorId`.
  void clearDecoderProviderOptionsHardwareVendorId(String provider) => withArena((arena) {
        check(OgaConfigClearDecoderProviderOptionsHardwareVendorId(handle, cString(arena, provider)));
      });

  /// Wraps `OgaConfigOverlay`.
  void overlay(String json) => withArena((arena) {
        check(OgaConfigOverlay(handle, cString(arena, json)));
      });

  /// Wraps `OgaCreateModelFromConfig`.
  Model createModelFromConfig() => withArena((arena) {
        final out = arena<Pointer<OgaModel>>();
        check(OgaCreateModelFromConfig(handle, out));
        return Model._(out.value);
      });

}

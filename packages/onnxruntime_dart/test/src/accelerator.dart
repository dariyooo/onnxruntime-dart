/// One accelerator a session can be asked for.
library;

/// An execution provider this platform can run a model on.
///
/// [name] is what a session calls it, which is not always what it was
/// registered as: ONNX Runtime knows its own providers by their own names.
class Accelerator {
  const Accelerator({
    required this.label,
    required this.name,
    required this.ensure,
    this.configuration = const {},
    this.skip,
  });

  /// What to call it in a test name.
  final String label;

  /// The provider name to put in `SessionOptions.providers`.
  final String name;

  /// Makes it usable. A no-op where nothing has to be registered.
  final Future<void> Function() ensure;

  /// Provider options it needs, if any.
  final Map<String, String> configuration;

  /// Why it cannot be used here, or null when it can.
  final String? skip;
}

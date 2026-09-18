/// What each runtime calls its execution providers.
///
/// Its own file, and importing nothing, so it can be tested without a browser.
/// The translation is the kind of thing that is only wrong at run time on one
/// platform, which is the most expensive place to find out.
library;

/// The spelling ONNX Runtime's WebAssembly build expects for a provider.
///
/// It matches the name exactly and rejects anything else, and its spellings
/// are not the ones native uses: `WebGPU` and `WEBNN` rather than the lower
/// case names a plugin is registered under. So a caller writing one name for
/// both platforms would work natively and fail here with "Unknown provider
/// name", which is a confusing thing to be told about a provider the build
/// definitely has.
///
/// Translated rather than documented, so that `providers: [(name: 'webgpu')]`
/// means the same thing everywhere. A name this does not know is passed
/// through: the runtime's own error lists what it accepts, and that is a
/// better message than one invented here.
String webProviderName(String name) => switch (name.toLowerCase()) {
      'webgpu' => 'WebGPU',
      'webnn' => 'WEBNN',
      'xnnpack' => 'XNNPACK',
      'cpu' => 'CPU',
      _ => name,
    };

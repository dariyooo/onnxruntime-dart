# Execution provider notes

Platform specific requirements for the GPU and NPU providers. You need this
only if you ship one of them, and only for the platform you ship to.

- **WebGPU** reaches Vulkan on Android and Linux, D3D12 or Vulkan on Windows,
  and Metal on Apple. Only the 64-bit Android ABIs, where Vulkan is dependable.
- **On Windows the WebGPU provider needs a shader compiler beside it.** This
  provider is built against Dawn's D3D12 backend, which compiles shaders
  through `dxcompiler.dll` and `dxil.dll`. Windows ships neither, and the
  provider loads them by name at the first compile rather than at load time, so
  a missing one looks like a working plugin that fails on its first run. Ship
  both next to `onnxruntime_providers_webgpu.dll`, from the upstream DirectX
  Shader Compiler release.
- **On Windows ARM take that compiler from the Windows SDK**, not from the DXC
  release. Every current DXC distribution, the GitHub release and the
  `Microsoft.Direct3D.DXC` NuGet package alike, puts ARM64EC under `bin/arm64`
  rather than ARM64: the PE header says AMD64, the load config carries a CHPE
  pointer, and there is no ARM64X relocation table, so a native ARM64 process
  refuses it and `LoadLibrary` fails with error 87. The SDK ships a real ARM64
  build under `bin/<version>/arm64`. Take a recent one: 10.0.26100.0 carries
  DXC 1.8 and works, while 10.0.22621.0 carries 1.6, which Dawn loads and then
  dies on with no message at all.
- **CUDA** ships against two toolkits and defaults to 12, which asks less of the
  driver. `build: cuda13` selects the other, and on arm64 it is the only one.
- **CUDA on Windows ARM needs the 13.4 developer preview.** That target is
  newer than the stable redistributables, which carry `libcublas` and
  `cuda_cudart` for `linux-sbsa`, `linux-x86_64` and `windows-x86_64` only. The
  toolkit for it lives under `packages.nvidia.com/prerelease/cuda/13.4.0`, and
  the provider wants `cublas64_13.dll` and `cublasLt64_13.dll` from it beside
  the plugin, as on x64. Take them from the `arm64` directories rather than the
  `_cross_x86_64` ones, which carry the same file names for x64 and fail to
  load with error 193. CI loads the plugin against this, so it is tested, but
  it is preview software and worth treating as such.
- **QNN** carries the Qualcomm AI Runtime with it. Not Android: there QNN is
  linked into a whole runtime rather than published as a loadable plugin.
- **On the web** nothing is loaded: WebGPU and WebNN are compiled into two of
  the three builds, so serving one is how you choose. CUDA and QNN have no web
  equivalent at all.

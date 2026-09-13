# Execution provider notes

Platform specific requirements for the GPU and NPU providers. You need this only
if you ship one of them, and only for the platform you ship to.

## WebGPU

WebGPU uses Vulkan on Android and Linux, D3D12 or Vulkan on Windows, and Metal
on Apple platforms. On Android it is built for the 64-bit ABIs only, because
Vulkan is not dependable on the hardware still running the 32-bit ones.

**On Windows you have to ship a shader compiler beside it.** The provider is
built against Dawn's D3D12 backend, which compiles shaders through
`dxcompiler.dll` and `dxil.dll`. Windows ships neither. The provider loads them
by name when it first compiles a shader, not when it loads, so a missing DLL
looks like a working plugin that fails on its first run. Put both next to
`onnxruntime_providers_webgpu.dll`, from the upstream DirectX Shader Compiler
release.

**On Windows ARM, take that compiler from the Windows SDK instead.** Every
current DXC distribution, both the GitHub release and the
`Microsoft.Direct3D.DXC` NuGet package, puts ARM64EC under `bin/arm64` rather
than ARM64. The PE header says AMD64, the load config carries a CHPE pointer,
and there is no ARM64X relocation table, so a native ARM64 process refuses it
and `LoadLibrary` fails with error 87. The SDK ships a real ARM64 build under
`bin/<version>/arm64`. Use a recent one: 10.0.26100.0 carries DXC 1.8 and works,
while 10.0.22621.0 carries 1.6, which Dawn loads and then crashes on with no
message.

## CUDA

The provider is built against two CUDA toolkits and defaults to 12, which
requires less of the driver. Select the other with `build: cuda13`. On arm64,
CUDA 13 is the only option.

**On Windows ARM you need the CUDA 13.4 developer preview.** The stable
redistributables carry `libcublas` and `cuda_cudart` for `linux-sbsa`,
`linux-x86_64` and `windows-x86_64` only. The toolkit for Windows ARM is under
`packages.nvidia.com/prerelease/cuda/13.4.0`, and the provider needs
`cublas64_13.dll` and `cublasLt64_13.dll` from it beside the plugin, the same as
on x64. Take them from the `arm64` directories, not the `_cross_x86_64` ones:
those have the same file names but are x64 builds and fail to load with error
193. CI does load the plugin against this, so it is tested, but it is preview
software.

## QNN

The QNN package ships the Qualcomm AI Runtime alongside the provider, because
the provider loads those libraries by name at run time.

There is no Android build. On Android, QNN is linked into a complete runtime
rather than published as a loadable plugin.

## The web

Nothing is loaded on the web. WebGPU and WebNN are compiled into two of the
three WebAssembly builds, so you choose them by choosing which build to serve.
CUDA and QNN have no web equivalent.

# Extending the package

Two things you are unlikely to need on day one, and are documented because
there is no way to work them out from the source.

The first is packaging an execution provider we do not ship. The second is
reaching the parts of ONNX Runtime's C API that the ordinary Dart API does not
cover.

## Adding a provider we do not package

A provider is a shared library exporting `CreateEpFactories`, and nothing about
the ones here is privileged. If you have one we do not ship, package it the same
way.

The only constraint is that `@Native` needs a compile-time constant asset id, so
it can only be written in the package that owns the asset. That is why providers
are packages rather than entries in a table here.

```dart
import 'dart:ffi';
import 'package:onnxruntime_dart/native.dart';

@Native<Void Function()>(
  symbol: 'CreateEpFactories',
  assetId: 'package:my_provider/provider',
)
external void _entryPoint();

bool registerMine() {
  final path = loadedLibraryPath(
    () => Native.addressOf<NativeFunction<Void Function()>>(_entryPoint).cast(),
    // Checked against the file the loader names. Every provider exports the
    // same symbol, so without this an asset you did not install resolves to
    // whichever library did, and the runtime is handed the wrong file.
    stem: 'onnxruntime_providers_mine',
  );
  if (path == null) return false;

  final environment = OrtEnvironment.instance();
  registerExecutionProviderLibrary(
    environment.api,
    environment.handle,
    name: 'mine',
    path: path,
  );
  return true;
}
```

Your package needs a build hook that installs the library as a code asset named
`provider`. `onnxruntime_hook` does that work, and `onnxruntime_ep_webgpu` is
fifty lines and is the whole example.

Already have the library on disk? `registerProviderLibrary(name:, path:)` takes
any path, no package required.

The same shape works for a custom operator library: export `RegisterCustomOps`
instead and pass the path to `SessionOptions(customOpsLibraries: [...])`.

## The complete C API

`onnxruntime_dart.dart` is the ergonomic surface and covers the common path. It
is not the ceiling.

```dart
import 'package:onnxruntime_dart/native.dart';
```

Every function in every API struct is reachable, because ffigen binds the
headers whole. Most also have a generated wrapper taking and returning Dart
values, allocating what the call needs and turning a failed `OrtStatus` into an
`OrtException`. A few dozen do not, where a signature defeats the generator, and
those are listed in `lib/src/bindings/api/unmapped.txt`.

Either way the raw function pointer is there, which is also the way in when a
wrapper cannot express what you need, such as a callback.

`native.dart` also holds what needs the loader rather than the runtime, which is
why provider registration lives there: the shared library has to compile for the
web, and that means no `dart:ffi` above the backend seam.

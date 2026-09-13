# Extending the package

Two things most applications do not need, documented here because you cannot
work either of them out from the source.

## Using a provider we do not package

An execution provider is a shared library that exports `CreateEpFactories`.
There is nothing special about the three we ship. If you have another one, such
as CANN or ROCm or one you built yourself, you can use it.

If the library is already on the machine, register it by path:

```dart
import 'package:onnxruntime_dart/onnxruntime_dart.dart';

registerProviderLibrary(
  name: 'cann',
  path: '/opt/cann/libonnxruntime_providers_cann.so',
);
```

Then request it by that name when you create a session, the same as any other
provider. Every session created after this call can use it. Call
`unregisterProviderLibrary('cann')` to unload it, after releasing every session
that used it.

That is the whole mechanism. Our provider packages do the same thing. What they
add is shipping the library and finding it again at run time.

### Shipping the library inside your app

If you want Flutter to bundle the library, it has to be a native asset, and
native assets come from packages. `@Native` needs a compile-time constant asset
id, so the binding can only live in the package that owns the asset.

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
    stem: 'onnxruntime_providers_mine',
  );
  if (path == null) return false;

  registerProviderLibrary(name: 'mine', path: path);
  return true;
}
```

Pass `stem` and do not skip it. Every provider exports the same symbol, so
without a name to check against, an asset you did not install can resolve to
whichever library did, and the runtime is handed the wrong file.

Your package also needs a build hook that installs the library as a code asset
named `provider`. `onnxruntime_hook` does that work, and `onnxruntime_ep_webgpu`
is a complete example in about 130 lines.

A custom operator library works the same way. Export `RegisterCustomOps` instead
of `CreateEpFactories`, and pass the path to
`SessionOptions(customOpsLibraries: [...])`.

## The complete C API

`onnxruntime_dart.dart` covers the common path. When you need something it does
not expose, import the native surface instead:

```dart
import 'package:onnxruntime_dart/native.dart';
```

Every function in every ONNX Runtime API struct is reachable, because ffigen
binds the headers whole. Most also have a generated wrapper that takes and
returns Dart values, allocates what the call needs, and turns a failed
`OrtStatus` into an `OrtException`.

Eleven functions have no generated wrapper, because their signatures are shapes
the generator cannot express. Ten of those are wrapped by hand instead and work
the same way. The eleventh, `GetOpaqueValue`, is not exposed at all: the caller
has to supply a struct whose layout only the custom operator that registered the
type knows, so there is no signature to write. All eleven are listed in
`lib/src/bindings/api/unmapped.txt`.

The raw function pointer is always available, which is also how you reach a call
a wrapper cannot express, such as one taking a callback.

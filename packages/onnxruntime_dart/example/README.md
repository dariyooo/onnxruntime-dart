# Examples

Both take a model path:

```
dart run example/short_lived_isolate.dart model.onnx
```

| File | Use it when |
| --- | --- |
| `short_lived_isolate.dart` | One inference, off the calling thread. `Isolate.run`, which is Dart's `compute()`. |
| `long_lived_isolate.dart` | Inference happens more than once. One isolate, one session, many requests. |

`Isolate.run` per inference rebuilds the session every call, and building one
runs graph optimisation. Use the long-lived shape whenever there is a second
inference.

Neither is needed just to keep a UI responsive. `await session.run(inputs)` hands
the work to ONNX Runtime's own threads without an isolate. Reach for an isolate
when your own pre- and post-processing should move too.

These are run by `test/example_test.dart`, so they cannot drift from the API.

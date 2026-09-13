# onnxruntime_harness

The Flutter app that CI uses to run the package tests on a real device or
simulator.

It exists because the Dart tests cannot run on Android or iOS on their own.
Those platforms load the runtime as a Flutter asset, so the tests have to run
inside a Flutter app. The harness is that app, and nothing more. The tests it
runs are the same ones `dart test` runs on the desktop platforms, driven from
`integration_test/`.

You do not need this to use the packages. If you want to run it by hand, start
a simulator or attach a device and run:

```sh
flutter test integration_test
```

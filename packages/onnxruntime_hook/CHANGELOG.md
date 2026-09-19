# Changelog

## 0.1.0+1

- Repackaged. The Dart API package was renamed from
  `onnxruntime_dart` to `onnxruntime_core`, so the description and
  readme here point at a package that exists.

## 0.1.0

- Unreleased. Split out of `onnxruntime_core` so that the packages installing
  binaries do not depend on the package that binds them. The build hook runner
  sees that as a cycle.

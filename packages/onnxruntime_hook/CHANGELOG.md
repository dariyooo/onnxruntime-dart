# Changelog

## 0.1.0

Unreleased. Split out of onnxruntime_dart so the packages that install
binaries do not depend on the package that binds them, which the build hook
runner sees as a cycle.

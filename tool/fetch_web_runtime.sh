#!/usr/bin/env bash
# Downloads the published WebAssembly runtime so browser tests can run it.
#
# Without this, `dart test -p chrome` compiles the runtime tests and skips
# them: the module has to be fetched, and a fresh checkout has nothing to
# fetch. CI runs this before the browser job for the same reason.
set -euo pipefail
cd "$(dirname "$0")/.."

build="${1:-web-wasm}"
tag="${2:-$(gh release list --limit 20 --json tagName \
  --jq '[.[] | select(.tagName | startswith("runtime-v"))][0].tagName')}"

target=packages/onnxruntime_dart/test/web_runtime
mkdir -p "$target"

echo "fetching $build from $tag"
gh release download "$tag" --pattern "$build.tar.gz" --dir "$target" --clobber
tar xzf "$target/$build.tar.gz" -C "$target"
rm -f "$target/$build.tar.gz"

loader=$(cd "$target" && ls *.mjs | head -1)
wasm=$(cd "$target" && ls *.wasm | head -1)

# package:test serves the package root, so the URL is the path within it.
cat > packages/onnxruntime_dart/test/src/web_runtime_config.dart <<EOF
// Written by tool/fetch_web_runtime.sh. Reset it with git checkout.
library;

const webRuntimeLoader = './web_runtime/$loader';
const webRuntimeWasm = './web_runtime/$wasm';
EOF

echo "ready: $loader"

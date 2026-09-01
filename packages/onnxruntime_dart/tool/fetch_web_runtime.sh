#!/usr/bin/env bash
# Puts a WebAssembly runtime where the browser tests can find it.
#
# The tests skip without one, because the build is 20 MB and does not belong in
# the repository. CI unpacks the build from the same run; this does the same
# thing locally from the most recent run that still has the artifact.
#
#   tool/fetch_web_runtime.sh                  # the plain, synchronous build
#   tool/fetch_web_runtime.sh web-wasm-webgpu  # the Asyncify build
#
# The two are worth running separately: they take different paths through the
# backend, and only the second one exercises the asynchronous calls.
set -euo pipefail

build="${1:-web-wasm}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
target="$here/packages/onnxruntime_dart/test/web_runtime"

run=$(gh run list --limit 30 --json databaseId --jq '.[].databaseId' | while read -r id; do
  if gh api "repos/:owner/:repo/actions/runs/$id/artifacts" \
      --jq '.artifacts[] | select(.expired == false) | .name' 2>/dev/null |
      grep -qx "onnxruntime-$build"; then
    echo "$id"
    break
  fi
done)

if [ -z "$run" ]; then
  echo "no unexpired onnxruntime-$build artifact in the last 30 runs." >&2
  echo "artifacts expire in a day, so build one or pick another." >&2
  exit 1
fi

echo "taking onnxruntime-$build from run $run"
staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT
gh run download "$run" -n "onnxruntime-$build" -D "$staging"

rm -rf "$target"
mkdir -p "$target"
tar xzf "$staging/runtime/$build.tar.gz" -C "$target"

loader=$(cd "$target" && ls ./*.mjs | head -1 | xargs basename)
wasm=$(cd "$target" && ls ./*.wasm | head -1 | xargs basename)

cat > "$here/packages/onnxruntime_dart/test/src/web_runtime_config.dart" <<EOF
/// Written by tool/fetch_web_runtime.sh from the $build build.
///
/// Not the checked-in version. Reset it with:
///   git checkout -- test/src/web_runtime_config.dart
library;

const webRuntimeLoader = './web_runtime/$loader';
const webRuntimeWasm = './web_runtime/$wasm';
EOF

echo "wrote test/src/web_runtime_config.dart -> $loader"
echo "now: dart test -p chrome"

#!/usr/bin/env bash
# Everything CI checks, in the order it checks it.
#
# Run before pushing. Twice a push has failed on formatting a file a narrower
# `dart format lib test` never looked at, and the static job gates the builds,
# so it costs a whole cycle.
set -euo pipefail
cd "$(dirname "$0")/.."

files=$(find packages -name '*.dart' -not -name '*.g.dart')
if [ -z "$files" ]; then
  echo "::error::found no Dart files to format-check"
  exit 1
fi
echo "format    $(echo "$files" | wc -l | tr -d ' ') files"
dart format --output=none --set-exit-if-changed $files > /dev/null

echo "analyze"
dart analyze --fatal-infos > /dev/null

echo "matrix"
python3 .github/scripts/test_matrix.py > /dev/null 2>&1

cd packages/onnxruntime_dart
echo "test      default"
dart test --exclude-tags exclusive --reporter failures-only
echo "test      exclusive"
dart test --tags exclusive --concurrency 1 --reporter failures-only
echo "test      chrome"
dart test -p chrome --reporter failures-only

echo "all clear"

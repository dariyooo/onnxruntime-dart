#!/usr/bin/env bash
# Runs the harness integration tests against a booted Android emulator.
#
# This lives in a file rather than inline in ci.yml because
# reactivecircus/android-emulator-runner does not run its `script:` input as a
# shell script. It splits the block on newlines and runs each line through its
# own `sh -c`. Two consequences, both of which have already cost a day:
#
#   1. A variable assigned on one line is gone on the next.
#   2. A backslash continuation does not continue anything. `sh -c 'flutter
#      test integration_test \'` hands flutter a literal `\` as a second
#      argument and drops every following line, so -d and the --dart-defines
#      never arrive. The stray `\` also resolves outside
#      <cwd>/integration_test while the real tests resolve inside, and that mix
#      is exactly what flutter_tools' _shouldRunAsIntegrationTests rejects with
#      "Integration tests and unit tests cannot be run in a single invocation".
#      That error named the test layout and meant the argument list.
#
# A one-line `script:` that calls this file makes both impossible by
# construction. Multi-line shell belongs somewhere a real shell reads it.
#
# Usage: run_device_tests_android.sh <has_webgpu> <has_genai>
# Working directory: integration/harness
set -euo pipefail

has_webgpu="${1:?has_webgpu argument is required}"
has_genai="${2:?has_genai argument is required}"

# Exactly "true" or "false", nothing else. bool.fromEnvironment treats every
# value that is not the literal string "true" as false, so "True", "yes" or an
# empty string silently disables the guarded group and the job stays green
# having tested less than it claims. ${x:?} rejects empty but accepts any
# other string, which is not enough. The iOS script validates the same way and
# this one did not, which is the asymmetry an audit found.
for pair in "has_webgpu=$has_webgpu" "has_genai=$has_genai"; do
  case "${pair#*=}" in
    true | false) ;;
    *)
      echo "::error::${pair%%=*} must be exactly true or false, got"\
        "'${pair#*=}'. Anything else reads as false in the test and turns a"\
        "group off without saying so."
      exit 1
      ;;
  esac
done

# What the emulator actually offers, before the tests run. This has now been
# answered: the image does carry a driver, at /vendor/lib64/hw/vulkan.ranchu.so,
# and vkjson builds a VkInstance on it, yet ONNX Runtime still reports CPU as
# the only provider with a device. So the gap is not a missing driver, it is
# that Dawn will not take the emulator's software Vulkan as an adapter. Kept
# because it is the evidence for that claim, and the answer would change if the
# image ever gained a real one.
adb shell getprop ro.hardware.vulkan || true
adb shell getprop ro.kernel.qemu.gles || true
adb shell 'ls /vendor/lib64/hw/vulkan.* 2>/dev/null' || true
adb shell 'cmd gpu vkjson 2>/dev/null | head -c 400' || true

# Named explicitly, the same as the iOS step does. Without -d, `flutter test`
# has to guess which device it is targeting.
device="$(adb devices | awk '/^emulator-/ {print $1; exit}')"
if [ -z "$device" ]; then
  echo "::error::No emulator in \`adb devices\`, so there is nothing to test on."
  adb devices
  exit 1
fi
echo "running on $device"

# Captured as well as shown, so the run can be checked afterwards. Passing by
# skipping is not passing, and the expanded reporter names every test and its
# skip reason, so the evidence is right there as long as somebody reads it.
out=$(mktemp)
status=0
flutter test integration_test \
  -d "$device" \
  --reporter expanded \
  --dart-define=HAS_WEBGPU="$has_webgpu" \
  --dart-define=HAS_GENAI="$has_genai" 2>&1 | tee "$out" || status=${PIPESTATUS[0]}

[ "$status" -eq 0 ] || exit "$status"

# The same check the iOS script makes, and for the same reason: a group that
# stopped running is indistinguishable from one that passed unless something
# insists on seeing it run. The marker is printed from a setUpAll inside the
# group, and a group-level skip stops setUpAll too, so it cannot be faked.
if [ "$has_genai" = true ]; then
  if grep -q "the GenAI group is running" "$out"; then
    echo "the GenAI group ran"
  else
    echo "::error::a GenAI library was staged but the GenAI group never ran."\
      "It skipped, or the app never got that far. Passing by skipping is not"\
      "passing."
    exit 1
  fi
fi

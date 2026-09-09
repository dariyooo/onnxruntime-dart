#!/usr/bin/env bash
#
# Runs the harness on an iOS simulator without depending on flutter's own VM
# service discovery, which is where this job used to hang.
#
# What goes wrong. `flutter test integration_test` learns the app's VM service
# URI in exactly one way: it runs `xcrun simctl spawn <udid> log stream` and
# waits for the app's "The Dart VM service is listening on ..." line to come
# past. That line reaches it through unified logging, and unified logging
# intermittently does not deliver it. ProtocolDiscovery.uri has no timeout, so
# a line that never arrives is not an error, it is silence until the step is
# killed. That is what pinned this step at its cap in roughly one job in three.
#
# It is not a race, and the difference matters because it means there is no
# timing to tune. Two measurements over the historical jobs say so.
#
# First, what flutter received on that stream after it started waiting. In all
# eight hangs it received nothing at all, not one line, for the whole 19 to 32
# minutes until the step was killed. In every healthy launch the URL arrives
# about 176 ms later. Throughout a hang the app is alive and foreground-focal
# in runningboardd's own log, and flutter's log stream subprocess is still
# running when the job cleans up orphans. So the stream is not slow and it is
# not dead, it starts and then silently never streams.
#
# Second, timing does not predict it. Across 34 launches in 27 jobs, the
# interval from flutter starting the stream to the app reporting its pid:
#
#   found the URL, n=23:  min 0.00s   median 3.49s   max 52.96s
#   hung,          n=11:  min 1.57s   median 4.68s   max 40.49s
#
# Launches that started in 0.00s and 0.01s found the line, and launches that
# took 30.17s and 40.49s missed it. Nothing else correlates either: every one
# of those jobs ran the same iPhone 16 Pro on the same iOS 18.5 with the same
# Xcode, and both runner images in the sample hang.
#
# So this is not a component to be tuned, it is a component that intermittently
# stops working, and the sound response is to stop depending on it.
#
# What this does instead. It reads the URI from the app's own stdout, over a
# pty this script owns, where no daemon sits between the app and the reader and
# there is nothing to lose the line. It keeps the system log as a second,
# independent channel, attached and proven to be delivering before the app
# starts rather than after. Then it hands the URI to
# `flutter drive --use-existing-app`, which connects to the URI it is given and
# reads no log at all.
#
# Both waits are bounded and say what they were waiting for. Whatever else
# happens here, it will not be silence.
#
# What it deliberately does not change. The app is still built by
# `flutter build ios --simulator --debug` and installed with `simctl install`,
# which is exactly what flutter_tools does itself in
# _setupUpdatedApplicationBundle, so the bundle, the native asset frameworks
# staged inside it and its signing are identical to what the old step ran.
# These tests exist to prove a library resolves out of an embedded framework,
# and that is worth nothing unless the bundle is the real one.
set -euo pipefail

simulator=$1
has_webgpu=$2
has_genai=$3

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# Long enough to cover a cold first attach with room to spare, short enough
# that a genuinely broken simulator fails loudly rather than sitting out the
# step timeout. Both of these replace what used to be an unbounded wait.
attach_deadline=90
announce_deadline=240

stream_pid=

stop_stream() {
  if [ -n "$stream_pid" ]; then
    kill "$stream_pid" 2>/dev/null || true
    wait "$stream_pid" 2>/dev/null || true
    stream_pid=
  fi
}

# Proves the log stream is attached and delivering, rather than assuming it
# after a sleep. `log show` announces its own noninteractive run, quoting its
# arguments, so asking it for a marker string makes the marker appear as a log
# message that the stream we just started has to carry. Nothing is delivered
# until the stream is really attached, which is the property being tested.
wait_for_stream() {
  local waited=0
  until grep -q ortdartprobe "$work/stream.txt" 2>/dev/null; do
    if [ "$waited" -ge "$attach_deadline" ]; then
      echo "::error::the simulator log stream delivered nothing in ${attach_deadline}s"
      return 1
    fi
    xcrun simctl spawn "$simulator" log show --last 1s --style compact \
      --predicate 'eventMessage CONTAINS "ortdartprobe"' >/dev/null 2>&1 || true
    sleep 2
    waited=$((waited + 2))
  done
  echo "the log stream is delivering after ${waited}s"
}

vm_service_uri() {
  sed -n 's/.*Dart VM service is listening on \(http:[^[:space:]]*\).*/\1/p' \
    "$work/app.txt" "$work/stream.txt" 2>/dev/null | head -1
}

run_one() {
  local target=$1
  local app=build/ios/iphonesimulator/Runner.app

  echo "::group::build $target"
  flutter build ios --simulator --debug --target="$target" \
    --dart-define=HAS_WEBGPU="$has_webgpu" \
    --dart-define=HAS_GENAI="$has_genai"
  echo "::endgroup::"

  # From the bundle rather than hardcoded, for the same reason flutter reads it
  # from there: it is the one value that cannot disagree with what was built.
  local bundle
  bundle=$(plutil -extract CFBundleIdentifier raw "$app/Info.plist")
  echo "running $target as $bundle"

  xcrun simctl terminate "$simulator" "$bundle" >/dev/null 2>&1 || true
  xcrun simctl install "$simulator" "$app"

  : > "$work/stream.txt"
  : > "$work/app.txt"

  # Channel one, the system log, the same source flutter uses. The difference
  # is entirely that this is attached and proven live before the app starts.
  xcrun simctl spawn "$simulator" log stream --style compact \
    --predicate 'eventMessage CONTAINS "Dart VM service"
              OR eventMessage CONTAINS "ortdartprobe"' \
    > "$work/stream.txt" 2>&1 &
  stream_pid=$!
  wait_for_stream

  # Channel two, the app's own stdout, which no daemon sits in front of. Two
  # channels because either alone would be a single point of failure, and the
  # whole defect being fixed here is a single point of failure.
  #
  # The launch arguments are the ones flutter passes, minus
  # --disable-vm-service-publication, which suppresses the mDNS advertisement
  # that would otherwise be a third way to find the service.
  xcrun simctl launch --console-pty "$simulator" "$bundle" \
    --enable-dart-profiling --enable-checked-mode --verify-entry-points \
    > "$work/app.txt" 2>&1 &
  local app_pid=$!

  local uri=''
  local waited=0
  while :; do
    uri=$(vm_service_uri)
    [ -n "$uri" ] && break
    if [ "$waited" -ge "$announce_deadline" ]; then
      echo "::error::no Dart VM service announcement in ${announce_deadline}s"
      echo "--- the app's own output"
      cat "$work/app.txt"
      echo "--- the system log stream"
      cat "$work/stream.txt"
      kill "$app_pid" 2>/dev/null || true
      stop_stream
      return 1
    fi
    sleep 2
    waited=$((waited + 2))
  done
  echo "the app announced $uri after ${waited}s"
  stop_stream

  # --use-existing-app takes the reuseApplication path, which connects to the
  # URI it is handed. No log is read and there is nothing left to race.
  local status=0
  flutter drive \
    --use-existing-app="$uri" \
    --driver=test_driver/integration_test.dart \
    --target="$target" \
    --device-id="$simulator" || status=$?

  kill "$app_pid" 2>/dev/null || true
  xcrun simctl terminate "$simulator" "$bundle" >/dev/null 2>&1 || true
  return "$status"
}

failed=0
for target in integration_test/*_test.dart; do
  if ! run_one "$target"; then
    echo "::error::$target failed"
    failed=1
  fi
done
exit "$failed"

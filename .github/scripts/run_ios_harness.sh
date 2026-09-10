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
# What this does instead, and be clear about what it does NOT do. The
# announcement still travels over unified logging. It was measured: `simctl
# launch --console-pty` carries the app's stdout, but the Flutter iOS engine
# routes the Dart VM's output through os_log rather than the process's file
# descriptors, so the pty yields exactly one line, the pid, and never the
# announcement. That channel is kept because it costs nothing and the run
# reports which channel actually supplied the URI, but it is not what makes
# this work.
#
# What makes this work is that the stream is verified and, if it is not
# delivering, thrown away and started again. The measured failure is a
# `log stream` subprocess that starts, stays alive, reports no error and
# delivers nothing for the entire run. flutter cannot see that, because it
# starts the stream and the app at the same instant and then waits forever on
# a channel it never confirmed. This proves the channel is carrying messages
# before the app exists, and re-establishes it if it is not, which turns the
# one failure mode that was observed into something recoverable.
#
# Every wait is bounded and says what it was waiting for. Whatever else
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

# Exactly "true" or "false", never anything else. These become
# --dart-define values, and bool.fromEnvironment treats every value that is
# not the string "true" as false. So an empty or misspelled argument would not
# fail here, it would silently turn a group off and the run would pass without
# it. That is the shape of the bug that hid on Android, and it is worth three
# lines to make it impossible rather than unlikely.
for flag in "$has_webgpu" "$has_genai"; do
  case "$flag" in
    true | false) ;;
    *)
      echo "::error::expected true or false, got '$flag'."\
        "A --dart-define that is not exactly \"true\" reads as false and"\
        "would skip a whole group silently."
      exit 1
      ;;
  esac
done

work=$(mktemp -d)

# These have to sum to less than the step's timeout-minutes, or the guillotine
# lands before the diagnosis and we are back to a job that dies without saying
# why, which is the entire thing being fixed. Keep that invariant if you change
# either number.
#
# The arithmetic against the step's 25 minute cap. Attach is 30s times 3
# attempts, the announcement is 120s, and the driver in
# test_driver/integration_test.dart is 300s, so one file can burn 8.5 minutes
# of bounded waiting. The unbounded part is the simulator boot, the two
# builds and the hooks, measured across healthy runs at 5m42s, 7m12s, 12m08s
# and 12m52s, so call it 13. 13 plus 8.5 is 21.5, which fits under 25, and
# only fits because a failure that is not the tests' fault stops the loop
# rather than letting the second file spend another 8.5 minutes discovering
# the same thing.
#
# Note what dominates: the Xcode builds varied from 24.7s to 196.6s for the
# same work on the same image, so the cap is sized against runner contention
# rather than against anything this script controls. If it ever starts biting,
# raise the cap and keep this sum underneath it. Do not reach for the bounds,
# because they are already twenty to fifty times the observed need and cutting
# them buys minutes off a case that does not happen while making the case that
# does happen fail sooner than it should.
#
# Measured healthy values, for scale: the log stream delivers in 2s and the
# announcement arrives in 2 to 6s, so these are between twenty and fifty times
# the observed need.
attach_deadline=30
attach_attempts=3
announce_deadline=120

stream_pid=

stop_stream() {
  if [ -n "$stream_pid" ]; then
    kill "$stream_pid" 2>/dev/null || true
    wait "$stream_pid" 2>/dev/null || true
    stream_pid=
  fi
}

# Set once stop_stream exists, so the handler cannot run before the function
# it calls is defined. Nothing above here starts a background process.
trap 'stop_stream; rm -rf "$work"' EXIT

# Proves the log stream is attached and delivering, rather than assuming it
# after a sleep. `log show` announces its own noninteractive run, quoting its
# arguments, so asking it for a marker string makes the marker appear as a log
# message that the stream we just started has to carry. Nothing is delivered
# until the stream is really attached, which is the property being tested.
#
# The filter echo has to be excluded or this proves nothing. `log stream`
# opens by printing "Filtering the log data using ..." with the predicate
# quoted back, and the predicate contains the marker, so a plain grep matches
# the stream's own header before it has carried a single event. That is how
# this was written, and it meant the check passed instantly on a stream that
# went on to deliver nothing at all. Found by faking a dead stream and
# watching the probe pass anyway.
wait_for_stream() {
  local waited=0
  until grep ortdartprobe "$work/stream.txt" 2>/dev/null \
    | grep -qv 'Filtering the log data'; do
    if [ "$waited" -ge "$attach_deadline" ]; then
      return 1
    fi
    xcrun simctl spawn "$simulator" log show --last 1s --style compact \
      --predicate 'eventMessage CONTAINS "ortdartprobe"' >/dev/null 2>&1 || true
    sleep 2
    waited=$((waited + 2))
  done
  echo "the log stream is delivering after ${waited}s"
}

# One file at a time, deliberately. Searching both at once would find the URI
# without saying which channel produced it, and that is the one thing about
# this fix worth knowing: the app's stdout is supposed to be doing the work,
# and the system log is the channel that intermittently delivers nothing. If
# the pty ever stops carrying it, the run has to say so rather than quietly
# falling back onto the mechanism this whole script exists to route around.
vm_service_uri() {
  sed -n 's/.*Dart VM service is listening on \(http:[^[:space:]]*\).*/\1/p' \
    "$1" 2>/dev/null | head -1
}

run_one() {
  local target=$1

  echo "::group::build $target"
  # One architecture, the simulator's own. `flutter test integration_test -d
  # <udid>` built through buildXcodeProject with a deviceID, which makes Xcode
  # target that device alone, so ARCHS was arm64 and the native asset hooks
  # were asked for ios-sim-arm64 only. `flutter build ios --simulator` has no
  # device to narrow it, so ARCHS becomes "arm64 x86_64" and the hooks are
  # asked for a GenAI library that upstream does not publish for ios-sim-x86_64
  # at all, which fails the build outright. Setting ARCHS restores exactly what
  # the old step built. FLUTTER_XCODE_<setting> is flutter's own documented way
  # to pass a build setting through to xcodebuild, and ARCHS is what reaches
  # the hooks as the IosArchs define.
  #
  # From uname because a simulator runs the host's architecture, so this stays
  # correct if these jobs ever move to an x86_64 macOS runner.
  local archs
  archs=$(uname -m)

  # Every failure below is checked by hand rather than left to `set -e`.
  # run_one is called from a conditional, and bash suppresses errexit for the
  # entire body of a function invoked that way, so an unchecked build failure
  # would fall through and test the previous target's bundle instead.
  local built=0
  FLUTTER_XCODE_ARCHS="$archs" FLUTTER_XCODE_ONLY_ACTIVE_ARCH=YES \
    flutter build ios --simulator --debug --target="$target" \
    --dart-define=HAS_WEBGPU="$has_webgpu" \
    --dart-define=HAS_GENAI="$has_genai" || built=$?
  echo "::endgroup::"
  if [ "$built" -ne 0 ]; then
    echo "::error::building $target failed"
    return 1
  fi

  # buildXcodeProject copies the bundle out of Xcode's Debug-iphonesimulator
  # into build/ios/iphonesimulator, which is the same path IOSApp
  # .simulatorBundlePath resolves to and the same one flutter installs from.
  # Globbed rather than named, so a renamed product is a clear failure here
  # instead of a confusing one later.
  local app
  app=$(echo build/ios/iphonesimulator/*.app)
  if [ ! -d "$app" ]; then
    echo "::error::no app bundle in build/ios/iphonesimulator after the build"
    ls -la build/ios || true
    return 1
  fi
  echo "built $app"
  find "$app/Frameworks" -maxdepth 1 -name '*.framework' 2>/dev/null | sed 's/^/  bundled: /'

  # From the bundle rather than hardcoded, for the same reason flutter reads it
  # from there: it is the one value that cannot disagree with what was built.
  local bundle
  bundle=$(plutil -extract CFBundleIdentifier raw "$app/Info.plist")
  echo "running $target as $bundle"

  xcrun simctl terminate "$simulator" "$bundle" >/dev/null 2>&1 || true
  if ! xcrun simctl install "$simulator" "$app"; then
    echo "::error::installing $app failed"
    return 1
  fi

  : > "$work/stream.txt"
  : > "$work/app.txt"

  # The system log, the same source flutter uses, and on iOS the only one that
  # actually carries the announcement. The difference from flutter is entirely
  # in the next few lines: this one is confirmed to be delivering before the
  # app is allowed to start, and a stream that will not deliver is discarded
  # and replaced rather than waited on. A dead stream is the measured failure,
  # and it is only unrecoverable if nobody looks.
  local attempt=1
  while :; do
    # Everything the app logs, not just the announcement. On iOS the engine
    # routes Dart's output through os_log, so this stream is the only place
    # the harness's own prints exist at all: not on the pty, and not in
    # flutter drive's output either. Narrowing it to the announcement is what
    # made the first version of the GenAI check impossible to satisfy. The
    # probe clause matches the `log show` process rather than the app, so it
    # has to sit outside the process filter.
    # Deliberately broken for the first ORT_FAULT_DEAD_STREAM attempts, so the
    # recovery below can be exercised on demand instead of waiting for the
    # real fault, which was intermittent at about one launch in three and has
    # not been seen since this script started proving the stream. The clause
    # matches nothing, which is exactly what a dead stream looks like from
    # here: a subprocess that starts, stays alive, reports no error and
    # delivers nothing. Unset in every normal run.
    local predicate='processImagePath ENDSWITH "Runner"
                OR eventMessage CONTAINS "ortdartprobe"'
    if [ "$attempt" -le "${ORT_FAULT_DEAD_STREAM:-0}" ]; then
      echo "::warning::ORT_FAULT_DEAD_STREAM is set, so attempt $attempt uses"\
        "a predicate that cannot match. This is a test of the restart path."
      predicate='eventMessage CONTAINS "ortdartnevermatch"'
    fi

    xcrun simctl spawn "$simulator" log stream --style compact \
      --predicate "$predicate" \
      > "$work/stream.txt" 2>&1 &
    stream_pid=$!
    if wait_for_stream; then
      break
    fi
    stop_stream
    if [ "$attempt" -ge "$attach_attempts" ]; then
      echo "::error::the simulator log stream delivered nothing in"\
        "$attach_attempts attempts of ${attach_deadline}s. This is the"\
        "channel the VM service announcement arrives on, so there is no"\
        "point launching the app."
      return 2
    fi
    echo "::warning::the log stream delivered nothing in ${attach_deadline}s,"\
      "discarding it and starting attempt $((attempt + 1))"
    : > "$work/stream.txt"
    attempt=$((attempt + 1))
  done

  # The app's own stdout. Measured to carry only the pid on iOS, because the
  # engine logs through os_log rather than the process's descriptors, so this
  # is a second opinion rather than a safety net. Kept anyway: it costs one
  # background process, it is where a crash on launch would show up, and if a
  # future engine ever does put the announcement on stdout the run will say so
  # rather than nobody noticing.
  #
  # The launch arguments are the ones flutter passes, minus
  # --disable-vm-service-publication, which suppresses the mDNS advertisement
  # that would otherwise be a third way to find the service.
  xcrun simctl launch --console-pty "$simulator" "$bundle" \
    --enable-dart-profiling --enable-checked-mode --verify-entry-points \
    > "$work/app.txt" 2>&1 &
  local app_pid=$!

  local uri=''
  local from_pty=''
  local from_log=''
  local waited=0
  while :; do
    from_pty=$(vm_service_uri "$work/app.txt")
    from_log=$(vm_service_uri "$work/stream.txt")
    # The pty first where both have it, so the reported source is the one the
    # fix depends on rather than whichever sed happened to reach first.
    uri=${from_pty:-$from_log}
    [ -n "$uri" ] && break
    if [ "$waited" -ge "$announce_deadline" ]; then
      echo "::error::no Dart VM service announcement in ${announce_deadline}s"
      echo "--- the app's own output"
      cat "$work/app.txt"
      echo "--- the system log stream"
      cat "$work/stream.txt"
      kill "$app_pid" 2>/dev/null || true
      stop_stream
      return 2
    fi
    sleep 2
    waited=$((waited + 2))
  done
  if [ -n "$from_pty" ] && [ -n "$from_log" ]; then
    echo "the app announced $uri after ${waited}s, on its stdout and in the log"
  elif [ -n "$from_pty" ]; then
    echo "the app announced $uri after ${waited}s, on its own stdout"
  else
    # The expected case on iOS, and stated rather than assumed so that the day
    # it changes is visible in the log.
    echo "the app announced $uri after ${waited}s, in the system log"
  fi
  # Deliberately left running. Everything the tests print arrives on it, and
  # stopping here is what threw that away in the earlier version.

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
  stop_stream

  # Always, not only on failure. The driver protocol itemises failures but
  # reduces a pass to "All tests passed", so this is the only place the
  # harness's own diagnostics survive: which library it resolved, which
  # providers reported a device, which groups skipped and why. That is what
  # `--reporter expanded` used to show. Grouped because the simulator
  # interleaves a lot of its own framework chatter into the same pty, and
  # unfiltered because guessing which of it is noise is how real output gets
  # dropped.
  # Both, labelled, because they carry different things and the difference is
  # not obvious. The pty holds the app's file descriptors, which on iOS means
  # the pid and a crash on startup and nothing else: the engine routes Dart's
  # output through os_log, so none of the test output is there. It was dumped
  # on its own once, in the belief that it held the diagnostics, and it held
  # one line. The system log is where the Dart side actually prints, and that
  # includes the expanded reporter's per-test lines, so dumping it gets back
  # everything `flutter test --reporter expanded` used to show. Without it a
  # green run says only "All tests passed" and a skipped group is invisible.
  echo "::group::the app's file descriptors, $target"
  cat "$work/app.txt"
  echo "::endgroup::"
  echo "::group::what the app logged, $target"
  cat "$work/stream.txt"
  echo "::endgroup::"

  # A skipped group is not a passing group. The driver cannot tell us which
  # tests ran, so the harness prints a marker from inside the GenAI group and
  # this insists on seeing it whenever CI staged a GenAI library. Without
  # this, a group that silently stopped running would keep reporting green,
  # which is the one failure mode nobody would notice.
  if [ "$has_genai" = true ] && [ "$target" = integration_test/layers_test.dart ]; then
    if grep -q "the GenAI group is running" "$work/stream.txt"; then
      echo "the GenAI group ran"
    else
      echo "::error::a GenAI library was staged but the GenAI group never ran."\
        "It skipped, or the app never got that far. Passing by skipping is"\
        "not passing."
      status=1
    fi
  fi

  return "$status"
}

# A test failure and a simulator that will not talk to us are different
# things. The first is worth carrying on for, because knowing both files'
# results is more useful than knowing one. The second is not: the second file
# would spend the same minutes failing the same way, and those minutes are the
# ones the step needs in order to report the first failure before its timeout.
# run_one says which it was, 1 for the tests and 2 for the harness around them.
failed=0
for target in integration_test/*_test.dart; do
  status=0
  run_one "$target" || status=$?
  case "$status" in
    0) ;;
    1)
      echo "::error::$target failed"
      failed=1
      ;;
    *)
      echo "::error::$target could not be run at all, so the rest are skipped"
      exit 1
      ;;
  esac
done
exit "$failed"

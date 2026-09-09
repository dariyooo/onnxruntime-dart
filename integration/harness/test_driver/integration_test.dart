// The driver half of `flutter drive`, which the iOS job uses instead of
// `flutter test integration_test`.
//
// `flutter test integration_test` learns the app's Dart VM service URI only by
// reading the simulator's system log, and unified logging intermittently loses
// the line that carries it. The tool has no timeout on that wait, so a lost
// line is silence until CI kills the step, which was happening to about one
// iOS job in three. `flutter drive --use-existing-app` is handed the URI
// directly and never reads a log, so the iOS job launches the app itself,
// reads the URI off the app's own stdout, and drives it through here. The
// measurements are in .github/scripts/run_ios_harness.sh.
//
// The driver protocol reports failures individually but reduces a passing run
// to "All tests passed", so the per-test lines that `--reporter expanded` used
// to print are not recoverable here. The job prints the app's own stdout
// instead, which is where the harness's diagnostics actually come from.
//
// Android is unaffected and still uses `flutter test integration_test`, so
// this file is only ever loaded by the iOS job.
import 'package:integration_test/integration_test_driver.dart';

// Ten rather than the twenty minute default. The whole point of the iOS job's
// launcher is that nothing waits without a bound, and a driver that outlives
// the tests by ten minutes would put one back. A healthy file finishes in
// under a minute.
Future<void> main() => integrationDriver(timeout: const Duration(minutes: 10));

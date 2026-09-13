/// What actually happened during a run, as opposed to what was asked for.
///
/// Asking for a provider and getting it are different things. ONNX Runtime
/// assigns nodes to providers one at a time, and a provider that cannot take a
/// node leaves it on the CPU without saying so. A session created with WebGPU
/// requested can therefore run entirely on the CPU and look, from the outside,
/// exactly like a session that got what it asked for.
///
/// The profile is where the difference shows. Each node's entry names the
/// provider that executed it, so counting them says which provider actually
/// ran, and how much of the model it took.
library;

import 'dart:convert';
import 'dart:io';

/// One unbroken stretch of nodes that ran on the same provider.
///
/// The interesting number in a split model is not how many nodes each provider
/// took, it is how many times execution crossed between them. Every crossing
/// copies tensors, so a model that alternates is often slower than one that
/// stays on the CPU throughout.
class RunSegment {
  const RunSegment(this.provider, this.nodes);

  final String provider;
  final int nodes;
}

/// What one run cost and who did the work.
class RunReport {
  const RunReport({
    required this.wallTime,
    required this.requested,
    required this.nodesByProvider,
    required this.warnings,
    this.segments = const [],
  });

  final Duration wallTime;

  /// The providers the session was created with, in the order they were tried.
  final List<String> requested;

  /// How many nodes each provider executed, largest first.
  final Map<String, int> nodesByProvider;

  /// The same nodes in execution order, with consecutive runs on one provider
  /// collapsed. `[cpu 60, webgpu 400, cpu 1]` means execution crossed twice.
  final List<RunSegment> segments;

  /// Anything worth saying about the difference between the two.
  final List<String> warnings;

  int get totalNodes =>
      nodesByProvider.values.fold(0, (total, count) => total + count);

  /// The provider that did most of the work, or null when nothing ran.
  String? get principal =>
      nodesByProvider.isEmpty ? null : nodesByProvider.keys.first;

  /// How many times execution moved from one provider to another.
  int get crossings => segments.isEmpty ? 0 : segments.length - 1;

  /// Whether the run fell back to the CPU despite being asked for something
  /// else.
  bool get fellBack =>
      requested.isNotEmpty &&
      nodesByProvider.keys.every((p) => p.startsWith('CPU'));
}

/// Reads a profile written by `Session.endProfiling` into a [RunReport].
///
/// The file is a JSON array of trace events. Node events carry an `args` map
/// with a `provider` in it; everything else is session and kernel bookkeeping
/// and is skipped. A profile with no node events at all means the run was
/// too short to sample or the file was truncated, which is reported rather
/// than shown as a run on no provider.
RunReport readProfile(
  String path, {
  required Duration wallTime,
  required List<String> requested,
}) {
  final warnings = <String>[];
  final counts = <String, int>{};
  final ordered = <(int, String)>[];

  final file = File(path);
  if (!file.existsSync()) {
    return RunReport(
      wallTime: wallTime,
      requested: requested,
      nodesByProvider: const {},
      warnings: const [
        'the runtime wrote no profile, so which provider ran '
            'cannot be told apart from which was asked for'
      ],
    );
  }

  try {
    final events = jsonDecode(file.readAsStringSync());
    if (events is List) {
      for (final event in events) {
        if (event is! Map) continue;
        final args = event['args'];
        if (args is! Map) continue;
        final provider = args['provider'];
        if (provider is String && provider.isNotEmpty) {
          counts[provider] = (counts[provider] ?? 0) + 1;
          // `ts` is microseconds since the session started. Sorting by it
          // recovers execution order, which the array is already in but is
          // not required to be.
          final ts = event['ts'];
          ordered.add((ts is int ? ts : ordered.length, provider));
        }
      }
    }
  } on FormatException catch (error) {
    warnings.add('the profile could not be read: ${error.message}');
  }

  if (counts.isEmpty) {
    warnings.add('the profile named no providers, so this says only that the '
        'run finished');
  }

  final sorted = Map.fromEntries(
    counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value)),
  );

  // Consecutive nodes on one provider collapse into a single segment, so the
  // result reads as the path execution actually took.
  ordered.sort((a, b) => a.$1.compareTo(b.$1));
  final segments = <RunSegment>[];
  for (final (_, provider) in ordered) {
    if (segments.isNotEmpty && segments.last.provider == provider) {
      segments[segments.length - 1] =
          RunSegment(provider, segments.last.nodes + 1);
    } else {
      segments.add(RunSegment(provider, 1));
    }
  }

  final report = RunReport(
    wallTime: wallTime,
    requested: requested,
    nodesByProvider: sorted,
    warnings: warnings,
    segments: segments,
  );

  if (report.fellBack) {
    warnings.add(
      'every node ran on the CPU although ${requested.join(', ')} '
      '${requested.length == 1 ? 'was' : 'were'} requested. The provider '
      'loaded and then took no nodes, which is the failure that looks most '
      'like success.',
    );
  } else if (requested.isNotEmpty && counts.length > 1) {
    final cpu = sorted.entries
        .where((e) => e.key.startsWith('CPU'))
        .fold(0, (total, e) => total + e.value);
    if (cpu > 0) {
      warnings.add(
        '$cpu of ${report.totalNodes} nodes stayed on the CPU, and execution '
        'crossed between providers ${report.crossings} times. Each crossing '
        'copies tensors between them, which is often slower than staying on '
        'one provider.',
      );
    }
  }

  return report;
}

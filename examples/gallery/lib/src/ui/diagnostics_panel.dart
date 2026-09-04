/// The panel that says who actually did the work.
///
/// The one part of this app that is not about the model. Which provider served
/// a run is the question most often answered by assumption, and the difference
/// between the answer and the assumption is where the interesting failures
/// live, so it gets its own place on the screen rather than a line in a log.
library;

import 'package:flutter/material.dart';

import '../diagnostics.dart';

class DiagnosticsPanel extends StatelessWidget {
  const DiagnosticsPanel({required this.report, super.key});

  final RunReport report;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final requested = report.requested.isEmpty
        ? 'CPU, by not asking'
        : report.requested.join(', ');

    return Card(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('What actually ran', style: theme.textTheme.titleSmall),
            const SizedBox(height: 12),
            _Row(label: 'Asked for', value: requested),
            _Row(
              label: 'Took',
              value: '${report.wallTime.inMilliseconds} ms',
            ),
            if (report.nodesByProvider.isEmpty)
              _Row(label: 'Served by', value: 'not recorded')
            else ...[
              const SizedBox(height: 8),
              for (final entry in report.nodesByProvider.entries)
                _ProviderBar(
                  name: entry.key,
                  nodes: entry.value,
                  total: report.totalNodes,
                ),
            ],
            if (report.warnings.isNotEmpty) ...[
              const SizedBox(height: 12),
              for (final warning in report.warnings)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 16,
                        color: theme.colorScheme.error,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(warning, style: theme.textTheme.bodySmall),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 90,
              child: Text(label, style: Theme.of(context).textTheme.bodySmall),
            ),
            Expanded(child: Text(value)),
          ],
        ),
      );
}

class _ProviderBar extends StatelessWidget {
  const _ProviderBar({
    required this.name,
    required this.nodes,
    required this.total,
  });

  final String name;
  final int nodes;
  final int total;

  @override
  Widget build(BuildContext context) {
    final share = total == 0 ? 0.0 : nodes / total;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(name)),
              Text(
                '$nodes of $total nodes',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(value: share, minHeight: 6),
          ),
        ],
      ),
    );
  }
}

/// One model: what it is, what it costs, and what it does when it runs.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../catalogue.dart';
import '../diagnostics.dart';
import '../generation.dart';
import '../inference.dart';
import '../store.dart';
import '../platform.dart';
import 'diagnostics_panel.dart';

class ModelPage extends StatefulWidget {
  const ModelPage({required this.spec, required this.store, super.key});

  final ModelSpec spec;
  final ModelStore store;

  @override
  State<ModelPage> createState() => _ModelPageState();
}

class _ModelPageState extends State<ModelPage> {
  bool _held = false;
  Progress? _progress;
  StreamSubscription<Progress>? _download;

  Uint8List? _image;
  ProviderChoice _provider = ProviderChoice.cpu;

  bool _running = false;
  Outcome? _outcome;
  Object? _error;

  final _first = TextEditingController(
    text: 'A man is playing a guitar on stage.',
  );
  final _second = TextEditingController(
    text: 'Someone performs music in front of an audience.',
  );
  final _passage = TextEditingController(
    text: 'ONNX Runtime is a cross platform inference engine. It runs models '
        'exported to the ONNX format on CPUs and on accelerators, and it is '
        'written in C++.',
  );
  final _question = TextEditingController(
    text: 'What language is ONNX Runtime written in?',
  );
  final _prompt = TextEditingController(
    text: 'Explain what an execution provider is, in two sentences.',
  );
  final _generated = StringBuffer();
  String? _device;

  @override
  void initState() {
    super.initState();
    widget.store.isComplete(widget.spec).then((held) {
      if (mounted) setState(() => _held = held);
    });
  }

  @override
  void dispose() {
    _download?.cancel();
    _first.dispose();
    _second.dispose();
    _passage.dispose();
    _question.dispose();
    _prompt.dispose();
    super.dispose();
  }

  void _fetch() {
    setState(() {
      _error = null;
      _progress = Progress(
        received: 0,
        total: widget.spec.bytes,
        file: widget.spec.model.name,
      );
    });
    _download = widget.store.fetch(widget.spec).listen(
          (progress) => setState(() => _progress = progress),
          onError: (Object error) => setState(() {
            _error = error;
            _progress = null;
          }),
          onDone: () async {
            final held = await widget.store.isComplete(widget.spec);
            if (mounted) {
              setState(() {
                _held = held;
                _progress = null;
              });
            }
          },
        );
  }

  Future<void> _run() async {
    setState(() {
      _running = true;
      _error = null;
      _outcome = null;
      _generated.clear();
    });
    try {
      final directory = widget.store.directoryFor(widget.spec);
      final outcome = switch (widget.spec.kind) {
        ModelKind.classifier => await runClassifier(
            spec: widget.spec,
            directory: directory,
            image: _image!,
            provider: _provider,
          ),
        ModelKind.detector => await runDetector(
            spec: widget.spec,
            directory: directory,
            image: _image!,
            provider: _provider,
          ),
        ModelKind.transformer => await runTransformer(
            spec: widget.spec,
            directory: directory,
            first: _first.text,
            second: _second.text,
            provider: _provider,
          ),
        ModelKind.recurrent => await runRecurrent(
            spec: widget.spec,
            directory: directory,
            passage: _passage.text,
            question: _question.text,
            provider: _provider,
          ),
        ModelKind.generative => await _generate(directory),
      };
      if (mounted) setState(() => _outcome = outcome);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  /// Generation is a stream, so it paints as it arrives rather than at the end.
  Future<Outcome> _generate(Directory directory) async {
    final clock = Stopwatch()..start();
    await for (final token in generate(
      directory: directory,
      prompt: _prompt.text,
      maximumTokens: 256,
      onReady: (ready) {
        if (mounted) setState(() => _device = ready.deviceType);
      },
    )) {
      _generated.write(token.text);
      if (mounted) setState(() {});
    }
    clock.stop();
    return Outcome(
      report: RunReport(
        wallTime: clock.elapsed,
        requested: _device == null ? const [] : [_device!],
        nodesByProvider: const {},
        warnings: const [
          'GenAI creates its own sessions from the model directory, so the '
              'node level accounting the other models show is not available '
              'here. What the model reports about itself is above.',
        ],
      ),
      lines: const [],
    );
  }

  bool get _canRun {
    if (!_held || _running) return false;
    return switch (widget.spec.kind) {
      ModelKind.classifier || ModelKind.detector => _image != null,
      _ => true,
    };
  }

  @override
  Widget build(BuildContext context) {
    final spec = widget.spec;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(spec.name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(spec.what, style: theme.textTheme.bodyLarge),
          const SizedBox(height: 12),
          Text(spec.exercises, style: theme.textTheme.bodySmall),
          const SizedBox(height: 16),
          _Provenance(spec: spec),
          const SizedBox(height: 16),
          _Download(
            spec: spec,
            held: _held,
            progress: _progress,
            onFetch: _fetch,
            onEvict: () async {
              await widget.store.evict(spec);
              if (mounted) setState(() => _held = false);
            },
          ),
          const Divider(height: 32),
          ..._inputs(context),
          const SizedBox(height: 16),
          Row(
            children: [
              FilledButton.icon(
                onPressed: _canRun ? _run : null,
                icon: _running
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.play_arrow),
                label: Text(_running ? 'Running' : 'Run'),
              ),
              const SizedBox(width: 16),
              if (spec.kind != ModelKind.generative)
                _ProviderPicker(
                  value: _provider,
                  onChanged: (choice) => setState(() => _provider = choice),
                ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            _ErrorCard(error: _error!),
          ],
          if (_generated.isNotEmpty) ...[
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SelectableText(_generated.toString()),
              ),
            ),
          ],
          if (_outcome != null) ...[
            const SizedBox(height: 16),
            if (_outcome!.lines.isNotEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final line in _outcome!.lines)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: SelectableText(line),
                        ),
                      if (_outcome!.detail != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          _outcome!.detail!,
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 12),
            DiagnosticsPanel(report: _outcome!.report),
          ],
        ],
      ),
    );
  }

  List<Widget> _inputs(BuildContext context) => switch (widget.spec.kind) {
        ModelKind.classifier || ModelKind.detector => [
            OutlinedButton.icon(
              onPressed: () async {
                final bytes = await pickImage();
                if (bytes != null && mounted) setState(() => _image = bytes);
              },
              icon: const Icon(Icons.image_outlined),
              label:
                  Text(_image == null ? 'Choose a picture' : 'Choose another'),
            ),
            if (_image != null) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(_image!, height: 180, fit: BoxFit.cover),
              ),
            ],
          ],
        ModelKind.transformer => [
            _Field(label: 'First sentence', controller: _first),
            const SizedBox(height: 12),
            _Field(label: 'Second sentence', controller: _second),
          ],
        ModelKind.recurrent => [
            _Field(label: 'Passage', controller: _passage, lines: 4),
            const SizedBox(height: 12),
            _Field(label: 'Question', controller: _question),
          ],
        ModelKind.generative => [
            _Field(label: 'Prompt', controller: _prompt, lines: 3),
            if (_device != null) ...[
              const SizedBox(height: 8),
              Text(
                'The model reports it is running on $_device.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
      };
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    this.lines = 1,
  });

  final String label;
  final TextEditingController controller;
  final int lines;

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        maxLines: lines,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
      );
}

class _Provenance extends StatelessWidget {
  const _Provenance({required this.spec});
  final ModelSpec spec;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Published by ${spec.source}',
                style: theme.textTheme.bodyMedium),
            const SizedBox(height: 4),
            SelectableText(spec.sourceUrl, style: theme.textTheme.bodySmall),
            if (spec.licence != null) ...[
              const SizedBox(height: 4),
              Text('Licensed ${spec.licence}',
                  style: theme.textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}

class _Download extends StatelessWidget {
  const _Download({
    required this.spec,
    required this.held,
    required this.progress,
    required this.onFetch,
    required this.onEvict,
  });

  final ModelSpec spec;
  final bool held;
  final Progress? progress;
  final VoidCallback onFetch;
  final VoidCallback onEvict;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (progress != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${humanBytes(progress!.received)} of '
            '${humanBytes(progress!.total)}  ·  ${progress!.file}',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: progress!.fraction),
        ],
      );
    }

    if (held) {
      return Row(
        children: [
          Icon(Icons.check_circle, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'On disk, ${humanBytes(spec.bytes)} across '
              '${spec.files.length} file${spec.files.length == 1 ? '' : 's'}.',
            ),
          ),
          TextButton(onPressed: onEvict, child: const Text('Delete')),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Downloading this will use ${humanBytes(spec.bytes)}'
          '${spec.files.length == 1 ? '' : ', across ${spec.files.length} files'}.',
        ),
        const SizedBox(height: 8),
        FilledButton.tonalIcon(
          onPressed: onFetch,
          icon: const Icon(Icons.download),
          label: Text('Download ${humanBytes(spec.bytes)}'),
        ),
      ],
    );
  }
}

class _ProviderPicker extends StatelessWidget {
  const _ProviderPicker({required this.value, required this.onChanged});

  final ProviderChoice value;
  final ValueChanged<ProviderChoice> onChanged;

  @override
  Widget build(BuildContext context) {
    final choices = providerChoices();
    if (choices.length < 2) {
      return Text(
        'CPU only in this build',
        style: Theme.of(context).textTheme.bodySmall,
      );
    }
    return SegmentedButton<String>(
      segments: [
        for (final choice in choices)
          ButtonSegment(value: choice.label, label: Text(choice.label)),
      ],
      selected: {value.label},
      onSelectionChanged: (selected) => onChanged(
        choices.firstWhere((choice) => choice.label == selected.first),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.error});
  final Object error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SelectableText(
          '$error',
          style: TextStyle(color: theme.colorScheme.onErrorContainer),
        ),
      ),
    );
  }
}

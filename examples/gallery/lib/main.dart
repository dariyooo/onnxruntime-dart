/// A gallery of upstream ONNX models, run through onnxruntime_dart.
///
/// It exists to exercise the packages rather than to demonstrate them. Every
/// model is fetched from the project that published it, its download size is
/// shown before it is spent, and every run reports which execution provider
/// actually served it rather than which one was asked for.
library;

import 'package:flutter/material.dart';
import 'package:onnxruntime_dart/onnxruntime_dart.dart';
import 'package:onnxruntime_web_webgpu_webnn/onnxruntime_web_webgpu_webnn.dart';

import 'src/catalogue.dart';
import 'src/store.dart';
import 'src/ui/model_page.dart';

void main() => runApp(const GalleryApp());

class GalleryApp extends StatelessWidget {
  const GalleryApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'ONNX Runtime gallery',
        theme: ThemeData(
          colorSchemeSeed: const Color(0xFF2C6E8F),
          useMaterial3: true,
        ),
        darkTheme: ThemeData(
          colorSchemeSeed: const Color(0xFF2C6E8F),
          brightness: Brightness.dark,
          useMaterial3: true,
        ),
        home: const CataloguePage(),
      );
}

class CataloguePage extends StatefulWidget {
  const CataloguePage({super.key});

  @override
  State<CataloguePage> createState() => _CataloguePageState();
}

class _CataloguePageState extends State<CataloguePage> {
  ModelStore? _store;
  String? _runtime;
  List<String> _providers = const [];
  Object? _error;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    try {
      // One call for every platform. Native links the runtime in and ignores
      // the web options; the web fetches the module named by them, which has
      // to finish before anything else touches the runtime.
      await openOnnxRuntime(
        web: const WebRuntimeOptions(ortLoaderUrl, wasm: ortWasmUrl),
      );
      final store = await ModelStore.open();
      // Reading the version is what actually loads the library, so a missing
      // or mismatched binary is reported here rather than on the first run.
      final version = runtimeVersion();
      final providers = availableProviders();
      if (!mounted) return;
      setState(() {
        _store = store;
        _runtime = version;
        _providers = providers;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = _store;
    return Scaffold(
      appBar: AppBar(
        title: const Text('ONNX Runtime gallery'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _runtime == null
                    ? 'opening the runtime'
                    : 'ONNX Runtime $_runtime  ·  '
                        '${_providers.length} provider'
                        '${_providers.length == 1 ? '' : 's'} available',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
        ),
      ),
      body: _error != null
          ? _Failure(error: _error!)
          : store == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: [
                    for (final spec in catalogue)
                      _ModelTile(spec: spec, store: store),
                    const SizedBox(height: 16),
                    _Footer(store: store),
                  ],
                ),
    );
  }
}

class _Failure extends StatelessWidget {
  const _Failure({required this.error});
  final Object error;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'The runtime did not open',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            SelectableText('$error'),
            const SizedBox(height: 12),
            Text(
              'The library is installed by onnxruntime_binaries through its '
              'build hook. If this is a fresh checkout, the hook has to run '
              'once before the app can start.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      );
}

class _ModelTile extends StatefulWidget {
  const _ModelTile({required this.spec, required this.store});
  final ModelSpec spec;
  final ModelStore store;

  @override
  State<_ModelTile> createState() => _ModelTileState();
}

class _ModelTileState extends State<_ModelTile> {
  bool? _held;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final held = await widget.store.isComplete(widget.spec);
    if (mounted) setState(() => _held = held);
  }

  @override
  Widget build(BuildContext context) {
    final spec = widget.spec;
    final held = _held;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: InkWell(
        onTap: () async {
          await Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => ModelPage(spec: spec, store: widget.store),
          ));
          await _refresh();
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      spec.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  Chip(
                    label: Text(spec.kind.label),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(spec.what),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(
                    held == true ? Icons.check_circle : Icons.cloud_download,
                    size: 16,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    held == null
                        ? '…'
                        : held
                            ? 'on disk, ${humanBytes(spec.bytes)}'
                            : '${humanBytes(spec.bytes)} to download',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const Spacer(),
                  Text(
                    spec.source,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Footer extends StatefulWidget {
  const _Footer({required this.store});
  final ModelStore store;

  @override
  State<_Footer> createState() => _FooterState();
}

class _FooterState extends State<_Footer> {
  int? _bytes;

  @override
  void initState() {
    super.initState();
    widget.store.bytesTotal().then((bytes) {
      if (mounted) setState(() => _bytes = bytes);
    });
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Text(
          _bytes == null
              ? ''
              : widget.store.isPersistent
                  ? 'Models are kept in ${widget.store.location}, '
                      '${humanBytes(_bytes!)} so far.'
                  : 'Models are held in ${widget.store.location}, '
                      '${humanBytes(_bytes!)} so far. Reloading the page '
                      'fetches them again: a browser has no directory to '
                      'keep them in.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
}

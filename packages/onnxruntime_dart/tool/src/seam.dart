/// What the two backends have in common, and what only one of them can do.
///
/// Both binding layers are generated from pinned headers, but nothing in
/// either header says that `CreateSessionFromArray` and `OrtCreateSession` are
/// the same operation. That correspondence is the one thing a parser cannot
/// recover, so it is declared here and everything else is derived from it:
/// which operations are portable, which belong to one platform, and what each
/// backend forwards to.
///
/// The table is small on purpose. Names that already agree are matched by rule
/// in [autoMatched]; this holds only the ones that genuinely differ, plus the
/// operations that exist on one side alone.
///
/// ## When the generator gets it wrong
///
/// An ONNX Runtime update can rename a function, split one into two, or add a
/// capability to one platform and not the other. [verify] fails the build with
/// the offending name rather than letting a backend drift, and the fix is one
/// of four edits, in order of preference:
///
///   1. A pure rename upstream: change the name in this table.
///   2. A new operation on both sides: add an entry. Nothing else to do.
///   3. A new operation on one side: add an entry naming only that side. It
///      lands on that platform's type and is invisible to portable code.
///   4. A shape change a table cannot express, such as one call becoming two:
///      write the method by hand in the matching `*_extra.dart` and list it in
///      [handWritten] so the coverage check knows it is deliberate.
library;

/// One operation the seam exposes.
final class Operation {
  const Operation(
    this.name, {
    this.native,
    this.wasm,
    this.nativeAlso = const [],
    this.note,
  });

  /// The Dart name, which is what an application sees.
  final String name;

  /// The C API function it forwards to, or null when native cannot do it.
  final String? native;

  /// The WebAssembly function it forwards to, or null when the web cannot.
  final String? wasm;

  /// Further C calls the operation needs, where one wasm call covers several.
  final List<String> nativeAlso;

  /// Why the mapping is not obvious, when it is not.
  final String? note;

  /// Portable when both sides have it. This is the whole availability rule:
  /// nothing is annotated, placement decides.
  bool get isPortable => native != null && wasm != null;

  bool get isNativeOnly => native != null && wasm == null;

  bool get isWebOnly => wasm != null && native == null;
}

/// Operations whose names differ between the two APIs, or that exist on one
/// side only. Everything else is matched by [autoMatched].
const correspondence = <Operation>[
  // The runtime itself. Native creates an OrtEnv and reads a version string;
  // the wasm build has one global init and exports neither.
  Operation('initialize',
      native: 'CreateEnv',
      wasm: 'OrtInit',
      note: 'wasm takes the thread count and log level here, native on the '
          'session options'),
  Operation('runtimeVersion',
      native: 'GetVersionString',
      // On OrtApiBase rather than OrtApi, which is why it is reached directly
      // rather than through a generated wrapper.
      note: 'the wasm build exports no version; the loader knows which build '
          'it fetched instead'),

  // Errors. Native returns an OrtStatus to read and release; wasm returns a
  // code and keeps the detail in one global.
  Operation('lastError', wasm: 'OrtGetLastError'),

  // Sessions.
  Operation('createSession',
      native: 'CreateSessionFromArray', wasm: 'OrtCreateSession'),
  Operation('inputOutputCount',
      native: 'SessionGetInputCount',
      nativeAlso: ['SessionGetOutputCount'],
      wasm: 'OrtGetInputOutputCount',
      note: 'one wasm call answers both counts'),
  Operation('inputOutputMetadata',
      native: 'SessionGetInputName',
      nativeAlso: [
        'SessionGetOutputName',
        'SessionGetInputTypeInfo',
        'SessionGetOutputTypeInfo',
      ],
      wasm: 'OrtGetInputOutputMetadata',
      note: 'one wasm call answers name, type and shape'),
  Operation('endProfiling',
      native: 'SessionEndProfiling', wasm: 'OrtEndProfiling'),

  // Tensors.
  Operation('createTensor',
      native: 'CreateTensorWithDataAsOrtValue', wasm: 'OrtCreateTensor'),
  Operation('tensorData',
      native: 'GetTensorMutableData',
      nativeAlso: ['GetTensorTypeAndShape'],
      wasm: 'OrtGetTensorData'),
  Operation('releaseTensor', native: 'ReleaseValue', wasm: 'OrtReleaseTensor'),
  Operation('createStringTensor',
      native: 'FillStringTensor',
      note: 'the wasm build has no string tensor path'),
  Operation('stringTensorData',
      native: 'GetStringTensorContent',
      note: 'the wasm build has no string tensor path'),

  // Allocation.
  Operation('free', native: 'AllocatorFree', wasm: 'OrtFree'),

  // Bindings.
  Operation('createBinding',
      native: 'CreateIoBinding', wasm: 'OrtCreateBinding'),
  Operation('releaseBinding',
      native: 'ReleaseIoBinding', wasm: 'OrtReleaseBinding'),
  Operation('clearBoundInputs',
      native: 'ClearBoundInputs', note: 'the wasm build clears outputs only'),

  // Providers and custom operators both mean opening a shared library, which
  // WebAssembly has no equivalent of: there they are compiled into the build.
  Operation('registerProviderLibrary',
      native: 'RegisterExecutionProviderLibrary'),
  Operation('unregisterProviderLibrary',
      native: 'UnregisterExecutionProviderLibrary'),
  Operation('addCustomOpsLibrary', native: 'RegisterCustomOpsLibrary_V2'),
  Operation('availableProviders', native: 'GetAvailableProviders'),

  // Training. Present in both, under different names: the wasm build prefixes
  // everything with OrtTraining and collapses the per-model input and output
  // calls the way it does for inference sessions.
  Operation('loadCheckpoint',
      native: 'LoadCheckpoint', wasm: 'OrtTrainingLoadCheckpoint'),
  Operation('releaseCheckpoint',
      native: 'ReleaseCheckpointState', wasm: 'OrtTrainingReleaseCheckpoint'),
  Operation('trainStep', native: 'TrainStep', wasm: 'OrtTrainingRunTrainStep'),
  Operation('copyParametersFromBuffer',
      native: 'CopyBufferToParameters',
      wasm: 'OrtTrainingCopyParametersFromBuffer'),
  Operation('trainingModelInputCount',
      native: 'TrainingSessionGetTrainingModelInputCount',
      nativeAlso: ['TrainingSessionGetEvalModelInputCount'],
      wasm: 'OrtTrainingGetModelInputOutputCount',
      note: 'one wasm call answers for both the train and eval models'),
  Operation('trainingModelInputName',
      native: 'TrainingSessionGetTrainingModelInputName',
      nativeAlso: ['TrainingSessionGetEvalModelInputName'],
      wasm: 'OrtTrainingGetModelInputOutputName'),

  // Web only.
  Operation('webGpuDevice',
      wasm: 'OrtGetWebGpuDevice',
      note: 'hands back the WebGPU device the runtime is using'),
];

/// Operations written by hand because their shape defeats the table.
///
/// Listed so the coverage check treats them as deliberate rather than missing.
const handWritten = <String>[
  // Native mutates a session-options object through a setter per field; the
  // wasm build takes every field as a parameter of OrtCreateSessionOptions.
  // No table expresses that, so each backend applies the options its own way.
  'applySessionOptions',
];

/// Prefixes the wasm API drops that the C API spells out.
///
/// Enough to match 25 of the 40 exported functions by rule, which is what
/// keeps [correspondence] to the ones that genuinely differ.
const _prefixes = ['Ort', 'OrtTraining'];
const _scopes = ['', 'Session', 'SessionOptions'];

/// The native name a wasm function matches by rule, or null.
String? autoMatched(String wasmName, Set<String> nativeNames) {
  for (final prefix in _prefixes) {
    if (!wasmName.startsWith(prefix)) continue;
    final bare = wasmName.substring(prefix.length);
    for (final scope in _scopes) {
      final candidate = '$scope$bare';
      if (nativeNames.contains(candidate)) return candidate;
    }
  }
  return nativeNames.contains(wasmName) ? wasmName : null;
}

/// Everything wrong with the table, as messages. Empty means it is correct.
///
/// Checks both directions. A name that no longer exists is a rename upstream;
/// a function in neither the table nor [autoMatched] is a new capability that
/// nobody has decided about yet.
List<String> verify({
  required Set<String> nativeNames,
  required Set<String> wasmNames,
}) {
  final problems = <String>[];

  for (final operation in correspondence) {
    for (final name in [
      if (operation.native != null) operation.native!,
      ...operation.nativeAlso,
    ]) {
      if (!nativeNames.contains(name)) {
        problems.add(
          '${operation.name}: the C API has no $name. It was renamed or '
          'removed upstream; fix the name in tool/src/seam.dart.',
        );
      }
    }
    final wasm = operation.wasm;
    if (wasm != null && !wasmNames.contains(wasm)) {
      problems.add(
        '${operation.name}: the WebAssembly build exports no $wasm. It was '
        'renamed or removed upstream; fix the name in tool/src/seam.dart.',
      );
    }
  }

  final claimed = {
    for (final operation in correspondence)
      if (operation.wasm != null) operation.wasm!,
  };
  for (final name in wasmNames) {
    if (claimed.contains(name)) continue;
    if (autoMatched(name, nativeNames) != null) continue;
    problems.add(
      '$name is exported by the WebAssembly build, matches no C API name by '
      'rule, and is not in tool/src/seam.dart. Add an entry saying what it '
      'corresponds to, or that it is web only.',
    );
  }

  return problems;
}

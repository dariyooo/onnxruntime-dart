@TestOn('vm')

/// Every member of ONNX Runtime's Python surface, and where it is reachable.
///
/// The Python package is the reference for what a user expects to find, not
/// for the shape of this API: we bind the C API, and Python binds the same one.
/// So this checks reachability rather than naming. A member is reachable when
/// the C call behind it has a wrapper, generated or hand-written.
library;

import 'dart:io';

import 'package:test/test.dart';

import 'src/paths.dart';

/// Python member to the C call behind it.
///
/// A null value means the member has no single C call: it is a session config
/// entry, or a property of the Python wrapper rather than of the runtime.
const _parity = <String, Map<String, String?>>{
  'SessionOptions': {
    'intra_op_num_threads': 'SetIntraOpNumThreads',
    'inter_op_num_threads': 'SetInterOpNumThreads',
    'execution_mode': 'SetSessionExecutionMode',
    'execution_order': null, // session.execution_order, a config entry
    'graph_optimization_level': 'SetSessionGraphOptimizationLevel',
    'enable_cpu_mem_arena': 'EnableCpuMemArena',
    'enable_mem_pattern': 'EnableMemPattern',
    'enable_mem_reuse': null, // session.use_memory_efficient_allocator
    'enable_profiling': 'EnableProfiling',
    'profile_file_prefix': 'EnableProfiling',
    'optimized_model_filepath': 'SetOptimizedModelFilePath',
    'log_severity_level': 'SetSessionLogSeverityLevel',
    'log_verbosity_level': 'SetSessionLogVerbosityLevel',
    'logid': 'SetSessionLogId',
    'use_deterministic_compute': 'SetDeterministicCompute',
    'use_per_session_threads': 'DisablePerSessionThreads',
    'add_session_config_entry': 'AddSessionConfigEntry',
    'get_session_config_entry': 'GetSessionConfigEntry',
    'add_free_dimension_override_by_name': 'AddFreeDimensionOverrideByName',
    'add_free_dimension_override_by_denotation': 'AddFreeDimensionOverride',
    'add_initializer': 'AddInitializer',
    'add_external_initializers': 'AddExternalInitializers',
    'register_custom_ops_library': 'RegisterCustomOpsLibrary_V2',
    'add_provider': 'SessionOptionsAppendExecutionProvider',
    'add_provider_for_devices': 'SessionOptionsAppendExecutionProvider_V2',
    'set_provider_selection_policy': 'SessionOptionsSetEpSelectionPolicy',
    'has_providers': 'GetAvailableProviders',
    'set_load_cancellation_flag': 'SessionOptionsSetLoadCancellationFlag',
  },
  'RunOptions': {
    'log_severity_level': 'RunOptionsSetRunLogSeverityLevel',
    'log_verbosity_level': 'RunOptionsSetRunLogVerbosityLevel',
    'logid': 'RunOptionsSetRunTag',
    'only_execute_path_to_fetches': null, // a run config entry
    'terminate': 'RunOptionsSetTerminate',
    'add_run_config_entry': 'AddRunConfigEntry',
    // No C counterpart: Python keeps its own copy of what it set.
    'get_run_config_entry': null,
  },
  'Session': {
    'run': 'Run',
    'run_async': 'RunAsync',
    'run_with_iobinding': 'RunWithBinding',
    'get_inputs': 'SessionGetInputTypeInfo',
    'get_outputs': 'SessionGetOutputTypeInfo',
    'get_overridable_initializers': 'SessionGetOverridableInitializerTypeInfo',
    'get_modelmeta': 'SessionGetModelMetadata',
    'get_providers': 'GetAvailableProviders',
    'get_provider_options': null, // read back from the options, not the session
    'set_providers': 'SessionOptionsAppendExecutionProvider',
    'enable_fallback': null, // Python-side retry, not a runtime call
    'disable_fallback': null,
    'end_profiling': 'SessionEndProfiling',
    'get_profiling_start_time_ns': 'SessionGetProfilingStartTimeNs',
    'get_input_memory_infos': 'SessionGetMemoryInfoForInputs',
    'get_output_memory_infos': 'SessionGetMemoryInfoForOutputs',
    'get_input_epdevices': 'SessionGetEpDeviceForInputs',
    'set_ep_dynamic_options': 'SetEpDynamicOptions',
  },
  'IOBinding': {
    'bind_input': 'BindInput',
    'bind_output': 'BindOutput',
    'bind_cpu_input': 'BindInput',
    'bind_ortvalue_input': 'BindInput',
    'bind_ortvalue_output': 'BindOutput',
    'clear_binding_inputs': 'ClearBoundInputs',
    'clear_binding_outputs': 'ClearBoundOutputs',
    'get_outputs': 'GetBoundOutputValues',
    'copy_outputs_to_cpu': 'GetBoundOutputValues',
    'synchronize_inputs': 'SynchronizeBoundInputs',
    'synchronize_outputs': 'SynchronizeBoundOutputs',
  },
};

void main() {
  late final Set<String> wrapped;

  setUpAll(() {
    final directory = Directory(fromPackage('lib/src/bindings/api'));
    wrapped = {
      for (final file in directory.listSync().whereType<File>())
        if (file.path.endsWith('.dart'))
          for (final match
              in RegExp(r'/// `(\w+)`').allMatches(file.readAsStringSync()))
            match.group(1)!,
      // Written by hand where the shape defeats both the generator and the
      // arena the manual wrappers use.
      ...const {'RunAsync'},
    };
  });

  for (final surface in _parity.entries) {
    group(surface.key, () {
      for (final member in surface.value.entries) {
        final call = member.value;
        if (call == null) continue;

        test(member.key, () {
          expect(
            wrapped,
            contains(call),
            reason: '${surface.key}.${member.key} needs $call, which has no '
                'wrapper. Add a rule to tool/src/types.dart, or write it in '
                'lib/src/bindings/api/manual.dart.',
          );
        });
      }
    });
  }

  test('the checklist covers what the design lists', () {
    // Guards the table above against quietly shrinking.
    expect(_parity['SessionOptions'], hasLength(28));
    expect(_parity['RunOptions'], hasLength(7));
    expect(_parity['Session'], hasLength(18));
    expect(_parity['IOBinding'], hasLength(11));
  });
}

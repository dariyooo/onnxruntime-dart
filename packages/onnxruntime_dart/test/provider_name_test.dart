@TestOn('vm')

/// The provider names the two runtimes accept.
///
/// ONNX Runtime's WebAssembly build matches a provider name exactly and
/// rejects any other spelling, and its spellings differ from the lower case
/// names a native plugin is registered under. A caller writing one name for
/// both platforms would work natively and fail on the web with "Unknown
/// provider name", about a provider the build definitely has.
///
/// Tested here rather than only in the browser suite because the translation
/// is a pure function and this is where a wrong spelling is cheapest to catch.
library;

import 'package:onnxruntime_dart/src/backend/provider_names.dart';
import 'package:test/test.dart';

void main() {
  group('the web spelling of a provider', () {
    test('is what ONNX Runtime asks for, not what native uses', () {
      // The exact strings from the runtime's own error message, which lists
      // 'WebGPU'/'WebGpuExecutionProvider' and 'WEBNN'/'WebNNExecutionProvider'.
      expect(webProviderName('webgpu'), 'WebGPU');
      expect(webProviderName('webnn'), 'WEBNN');
    });

    test('does not care how the caller cased it', () {
      for (final spelling in ['webgpu', 'WebGPU', 'WEBGPU', 'WebGpu']) {
        expect(webProviderName(spelling), 'WebGPU', reason: spelling);
      }
    });

    test('passes an unknown name through', () {
      // The runtime's own error lists what it accepts, which is a better
      // message than one invented here.
      expect(webProviderName('coreml'), 'coreml');
      expect(webProviderName('something-new'), 'something-new');
    });
  });
}

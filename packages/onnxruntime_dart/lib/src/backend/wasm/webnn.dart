/// The part of a WebNN session that lives in JavaScript.
///
/// The provider does not create its own context. It reads `Module`'s
/// `currentContext`, which has to be set before the session is created and
/// handed to the session afterwards, so the whole handshake is on this side:
///
/// ```
/// Module.currentContext = await Module.webnnCreateMLContext({deviceType})
/// handle = await _OrtCreateSession(...)
/// Module.webnnRegisterMLContext(handle, Module.currentContext)
/// Module.currentContext = undefined
/// ```
///
/// Getting this wrong does not degrade to the CPU: the provider throws
/// "Failed to create WebNN context" from its constructor, which is what
/// happens when nothing sets it at all.
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'module.dart';

extension OrtWebNnApi on OrtModule {
  /// The context the next session will take, and nothing else's business.
  @JS('currentContext')
  external JSAny? get currentContext;

  @JS('currentContext')
  external set currentContext(JSAny? value);

  @JS('webnnCreateMLContext')
  external JSPromise<JSAny> webnnCreateMLContext(JSAny options);

  @JS('webnnRegisterMLContext')
  external void webnnRegisterMLContext(JSNumber session, JSAny context);
}

/// Whether this build can actually run a WebNN session.
///
/// Having the provider compiled in is not enough. `post-webnn.js` defines
/// `webnnCreateMLContext` and the rest inside `webnnInit`, which takes an
/// object implementing ONNX Runtime's own `WebNNBackend`: roughly a thousand
/// lines of TypeScript that hand out MLTensor ids and move data between the
/// WebAssembly heap and an MLTensor. Nothing calls it here, so a build can
/// export `webnnInit` and still have no usable WebNN.
bool hasWebNn(OrtModule module) => module.has('webnnCreateMLContext');

/// What to tell someone whose build has WebNN compiled in but not wired up.
const whyWebNnUnavailable =
    'this build has the WebNN provider compiled in, but WebNN is not usable '
    'from this package. Unlike WebGPU, whose implementation is inside the '
    "WebAssembly module, WebNN's tensor management lives in ONNX Runtime's "
    'JavaScript layer: Module.webnnInit has to be handed a WebNNBackend that '
    'reserves MLTensor ids and moves data in and out of them, and this '
    'package has no equivalent. Use WebGPU instead, which needs none of it.';

/// The provider name ONNX Runtime knows WebNN by, however it was written.
bool isWebNn(String name) => name.toUpperCase() == 'WEBNN';

/// Creates the context a WebNN session will use and parks it on the module.
///
/// [configuration] takes the same keys the JavaScript API does, `deviceType`
/// and `powerPreference`, and an absent one means the browser chooses.
Future<JSAny> beginWebNnSession(
  OrtModule module,
  Map<String, String> configuration,
) async {
  final options = JSObject();
  for (final entry in configuration.entries) {
    options.setProperty(entry.key.toJS, entry.value.toJS);
  }

  if (!hasWebNn(module)) {
    throw UnsupportedError('WebNN: $whyWebNnUnavailable');
  }

  final context = await module.webnnCreateMLContext(options).toDart;
  module.currentContext = context;
  return context;
}

/// Hands the context to the session that was just created, and unparks it.
///
/// Always after the session, and always even if it failed, because a context
/// left on the module would be picked up by whatever is created next.
void endWebNnSession(OrtModule module, JSAny? context, int session) {
  if (context != null && session != 0) {
    module.webnnRegisterMLContext(session.toJS, context);
  }
  module.currentContext = null;
}

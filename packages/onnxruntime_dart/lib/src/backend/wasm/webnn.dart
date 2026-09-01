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

  @JS('webnnInit')
  external void webnnInit(JSArray<JSAny> params);
}

/// Whether this build has the WebNN glue compiled into it.
///
/// Only that the glue exists. It stays inert until [wireWebNn] runs.
bool hasWebNn(OrtModule module) => module.has('webnnInit');

@JS('navigator')
external JSObject get _navigator;

/// Whether the browser exposes WebNN at all.
bool browserHasWebNn() => _navigator.has('ml');

extension type _Ml(JSObject _) implements JSObject {
  external JSPromise<JSAny> createContext(JSAny options);
}

/// Refuses a call on the MLTensor path, by name.
///
/// Declared as returning a value rather than throwing straight from the
/// closure, because a function that only ever throws types as `Never` and
/// cannot cross into JavaScript.
JSAny? _refuse(String name) => throw UnsupportedError(
      'WebNN: ONNX Runtime called $name, which is part of the MLTensor path '
      'this package does not implement. Data stays on ordinary tensors here, '
      'so reaching this is a change in what the runtime asks for rather than '
      'something you did.',
    );

/// The contexts sessions are using, so one is not collected while it runs.
final _contexts = <int, JSAny>{};

var _wired = false;

/// Hands ONNX Runtime the JavaScript side it expects, implemented here.
///
/// `post-webnn.js` leaves every WebNN entry point unset until `webnnInit` is
/// called with a backend object and seven callbacks, and then defines them as
/// one-line forwards onto that object. Upstream passes its own TypeScript
/// backend; nothing stops this passing one, which is what this does.
///
/// Only the parts a session on ordinary tensors reaches are implemented. The
/// MLTensor paths, where a model's data would live on the accelerator between
/// runs, throw by name rather than returning something wrong, so if one is
/// ever reached it says which.
void wireWebNn(OrtModule module) {
  if (_wired) return;
  _wired = true;

  JSFunction unimplemented(String name) => (() => _refuse(name)).toJS;

  final backend = JSObject()
    ..setProperty(
      'createMLContext'.toJS,
      ((JSAny? options) =>
          _Ml(_navigator.getProperty<JSObject>('ml'.toJS)).createContext(
            options ?? JSObject(),
          )).toJS,
    )
    // A session is told which context it got; keeping it alive is all this
    // has to do, since the provider holds its own reference.
    ..setProperty('onRunStart'.toJS, ((JSAny? _) {}).toJS)
    ..setProperty('onRunEnd'.toJS, ((JSAny? _) {}).toJS)
    ..setProperty(
      'onReleaseSession'.toJS,
      ((JSNumber session) => _contexts.remove(session.toDartInt)).toJS,
    )
    // No graph input or output is an MLTensor here, so the runtime keeps
    // moving data through the heap as it does for the CPU provider.
    ..setProperty(
        'isGraphInput'.toJS, ((JSAny? _, JSAny? __) => false.toJS).toJS)
    ..setProperty(
        'isGraphOutput'.toJS, ((JSAny? _, JSAny? __) => false.toJS).toJS)
    ..setProperty(
      'isGraphInputOutputTypeSupported'.toJS,
      ((JSAny? _, JSAny? __, JSAny? ___) => false.toJS).toJS,
    )
    ..setProperty(
        'registerGraphInput'.toJS, unimplemented('registerGraphInput'))
    ..setProperty(
        'registerGraphOutput'.toJS, unimplemented('registerGraphOutput'))
    ..setProperty('registerMLTensor'.toJS, unimplemented('registerMLTensor'))
    ..setProperty(
        'createTemporaryTensor'.toJS, unimplemented('createTemporaryTensor'))
    ..setProperty('createMLTensorDownloader'.toJS,
        unimplemented('createMLTensorDownloader'));

  module.webnnInit([
    backend,
    unimplemented('reserveTensorId'),
    unimplemented('releaseTensorId'),
    unimplemented('ensureTensor'),
    unimplemented('uploadTensor'),
    unimplemented('downloadTensor'),
    // Called once per session, straight after it is created.
    ((JSNumber session, JSAny context) {
      _contexts[session.toDartInt] = context;
    }).toJS,
    ((JSAny? _) {}).toJS,
  ].toJS);
}

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
    throw UnsupportedError(
      'WebNN: this build has no WebNN glue, so it was not compiled with the '
      'provider. Serve a build that was.',
    );
  }
  if (!browserHasWebNn()) {
    throw UnsupportedError(
      'WebNN: this browser does not expose navigator.ml. Chromium has it '
      'behind --enable-features=WebMachineLearningNeuralNetwork.',
    );
  }
  wireWebNn(module);

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

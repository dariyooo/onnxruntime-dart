/// One small model, embedded so the shared tests need no filesystem.
///
/// The corpus lives in the submodule and is read with `dart:io`, which the
/// browser has no equivalent of. Rather than making the portable tests
/// unportable, the smallest model that exercises a real graph is carried here:
/// abs_free_dimensions.onnx, 137 bytes, a single Abs over a float tensor with free
/// dimensions.
///
/// Free dimensions matter: they make the input shape the caller's choice, so
/// one model serves every shape the tests want to try.
library;

import 'dart:convert';
import 'dart:typed_data';

/// The model, ready to hand to `Session.fromBytes`.
Uint8List absModel() => base64.decode(_absModel);

/// Its single input and output names, from the graph itself.
const absInput = 'x';
const absOutput = 'y';

const _absModel =
    'CAMSDGJhY2tlbmQtdGVzdDpzCgsKAXgSAXkiA0FicxIIdGVzdF9hYnNaOQoBeBI0'
    'CjIIARIuChISBERpbTEaCkRBVEFfQkFUQ0gKFBIERGltMhoMREFUQV9DSEFOTkVM'
    'CgIIBWIfCgF5EhoKGAgBEhQKBhIERGltMQoGEgREaW0yCgIIBUICEAk=';

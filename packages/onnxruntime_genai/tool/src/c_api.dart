/// Reads the GenAI C API out of the pinned header.
///
/// The header is authoritative for names, parameter direction and ownership.
/// Everything this file does is turn its declarations into something the
/// emitter can walk, without deciding anything about how they are wrapped.
library;

import 'dart:io';

import 'types.dart';

/// One parameter of a C function.
final class CParameter {
  CParameter({required this.name, required this.type});

  final String name;
  final String type;

  /// Whether this is the out-parameter a constructor writes its handle into.
  ///
  /// The convention upstream follows without exception: the last parameter of
  /// a function that returns `OgaResult*` is where the result goes, and it is
  /// a pointer to whatever is being produced.
  bool get isHandleOut => type.endsWith('**');

  /// The handle type this points at, for an out-parameter.
  String get pointee =>
      type.replaceAll('*', '').replaceAll('const ', '').trim();
}

/// One exported function.
final class CFunction {
  CFunction({
    required this.name,
    required this.returns,
    required this.parameters,
    this.takesCallback = false,
    this.documentation = '',
  });

  final String name;
  final String returns;
  final List<CParameter> parameters;

  /// The doc comment above the declaration, which is where upstream says who
  /// owns what it hands back.
  final String documentation;

  /// Whether a string this produces belongs to the caller.
  ///
  /// GenAI transfers a string only where it says so. `OgaTokenizerDecode` is
  /// documented "must be freed with OgaDestroyString"; `OgaStringArrayGetString`
  /// says nothing, and its string belongs to the array. Freeing a borrowed one
  /// aborts the process, so this is read rather than assumed.
  bool get transfersString =>
      documentation.contains('OgaDestroyString') ||
      documentation.contains('must be freed');

  /// Whether the signature holds a function pointer this does not read.
  ///
  /// Kept apart from an empty parameter list, which is what a niladic function
  /// has. Emitting from one as though it were the other produces a call with
  /// no arguments that does not compile.
  final bool takesCallback;

  /// Whether failure arrives as a result object rather than in the return.
  bool get canFail => returns == 'OgaResult*';

  /// Whether this releases a handle rather than doing work with one.
  bool get isDestructor => name.startsWith('OgaDestroy');

  /// The handle this belongs to, or null if it belongs to no type.
  ///
  /// Taken from the first parameter rather than from the name. A name is a
  /// convention and drifts; the type a function takes is what it is.
  String? get owner {
    for (final parameter in parameters) {
      final type = parameter.pointee;
      if (type.startsWith('Oga') && !notAHandle.contains(type)) return type;
    }
    return null;
  }
}

/// Types that begin with Oga and are not opaque handles.
///
/// OgaResult is how failure is reported and support.dart owns it. OgaElementType
/// is an enum passed by value. Neither is something a caller holds and releases,
/// and taking either for a handle produces a class with no destructor.
const notAHandle = {'OgaResult', 'OgaElementType'};

/// Every function the header exports, in declaration order.
List<CFunction> readCApi(File header) {
  // Continuations joined first: a declaration may be wrapped across lines, and
  // matching per line would silently drop the long ones.
  final text = header
      .readAsStringSync()
      .replaceAll(RegExp(r'\s*\n\s*'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ');

  // The doc comment is part of the match so that ownership travels with the
  // declaration it belongs to.
  final declaration = RegExp(
    r'(/\*\*.*?\*/)?\s*OGA_EXPORT\s+([A-Za-z_0-9 ]+?\**)\s*OGA_API_CALL\s+'
    r'(\w+)\s*\(([^;]*?)\)\s*;',
  );

  final functions = <CFunction>[];
  for (final match in declaration.allMatches(text)) {
    final documentation = match.group(1) ?? '';
    final returns = match.group(2)!.replaceAll(' *', '*').trim();
    final name = match.group(3)!;
    final rawParameters = match.group(4)!.trim();

    // A function pointer parameter has parentheses in it, which also means the
    // list cannot be split on commas: the callback's own parameters are in
    // there. Handled whole where the callback is the only parameter, which is
    // how the header declares every one of them. Anything else is reported
    // rather than guessed at.
    if (rawParameters.contains('(')) {
      final callback = _callbackParameter(rawParameters);
      if (callback == null) {
        functions.add(CFunction(
          name: name,
          returns: returns,
          parameters: [],
          takesCallback: true,
          documentation: documentation,
        ));
        continue;
      }
      functions.add(CFunction(
        name: name,
        returns: returns,
        parameters: [callback],
        documentation: documentation,
      ));
      continue;
    }

    final parameters = <CParameter>[];
    if (rawParameters.isNotEmpty && rawParameters != 'void') {
      for (final piece in rawParameters.split(',')) {
        final part = piece.trim();
        final split = RegExp(r'^(.*?[ *])(\w+)$').firstMatch(part);
        parameters.add(
          split == null
              // Unnamed, which upstream does for destructors: OgaDestroyString
              // is declared as taking `const char*` with no parameter name.
              ? CParameter(name: 'value', type: part.replaceAll(' *', '*'))
              : CParameter(
                  name: split.group(2)!,
                  type: split.group(1)!.replaceAll(' *', '*').trim(),
                ),
        );
      }
    }
    functions.add(CFunction(
      name: name,
      returns: returns,
      parameters: parameters,
      documentation: documentation,
    ));
  }
  return functions;
}

/// A lone function-pointer parameter, spelled the way ffigen types it.
///
/// `void (*callback)(const char* string, size_t length)` becomes
/// `Pointer<NativeFunction<Void Function(Pointer<Char>, Size)>>`, which is what
/// the generated binding declares, so the wrapper can pass it straight on.
/// Returns null when any part of it is a type this does not know, so an
/// unfamiliar callback is reported rather than mis-declared.
CParameter? _callbackParameter(String raw) {
  final match = RegExp(
    r'^([\w ]+?[\w*])\s*\(\s*\*\s*(\w+)\s*\)\s*\((.*)\)$',
  ).firstMatch(raw.trim());
  if (match == null) return null;

  final returns = nativeTypeOf(match.group(1)!);
  if (returns == null) return null;

  final arguments = <String>[];
  final inner = match.group(3)!.trim();
  if (inner.isNotEmpty && inner != 'void') {
    for (final piece in inner.split(',')) {
      final part = piece.trim();
      // The argument may or may not be named; the type is what matters.
      final type = RegExp(r'^(.*?[ *])\w+$').firstMatch(part)?.group(1) ?? part;
      final mapped = nativeTypeOf(type.replaceAll(' *', '*').trim());
      if (mapped == null) return null;
      arguments.add(mapped);
    }
  }

  return CParameter(
    name: match.group(2)!,
    type: 'Pointer<NativeFunction<$returns Function(${arguments.join(', ')})>>',
  );
}

/// Reads the GenAI C API out of the pinned header.
///
/// The header is authoritative for names, parameter direction and ownership.
/// Everything this file does is turn its declarations into something the
/// emitter can walk, without deciding anything about how they are wrapped.
library;

import 'dart:io';

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
  String get pointee => type.replaceAll('*', '').replaceAll('const ', '').trim();
}

/// One exported function.
final class CFunction {
  CFunction({
    required this.name,
    required this.returns,
    required this.parameters,
  });

  final String name;
  final String returns;
  final List<CParameter> parameters;

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
      if (type.startsWith('Oga') && type != 'OgaResult') return type;
    }
    return null;
  }
}

/// Every function the header exports, in declaration order.
List<CFunction> readCApi(File header) {
  // Continuations joined first: a declaration may be wrapped across lines, and
  // matching per line would silently drop the long ones.
  final text = header
      .readAsStringSync()
      .replaceAll(RegExp(r'\s*\n\s*'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ');

  final declaration = RegExp(
    r'OGA_EXPORT\s+([A-Za-z_0-9 ]+?\**)\s*OGA_API_CALL\s+(\w+)\s*\(([^;]*?)\)\s*;',
  );

  final functions = <CFunction>[];
  for (final match in declaration.allMatches(text)) {
    final returns = match.group(1)!.replaceAll(' *', '*').trim();
    final name = match.group(2)!;
    final rawParameters = match.group(3)!.trim();

    // A function pointer parameter has parentheses in it. Those are the log
    // and streaming callbacks, which need a hand-written wrapper rather than
    // a generated one, so they are reported instead of guessed at.
    if (rawParameters.contains('(')) {
      functions.add(CFunction(name: name, returns: returns, parameters: []));
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
    functions.add(
      CFunction(name: name, returns: returns, parameters: parameters),
    );
  }
  return functions;
}

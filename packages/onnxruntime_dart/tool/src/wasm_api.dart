/// Reads the WebAssembly build's exported API.
///
/// A different shape from the C API: free functions marked
/// `EMSCRIPTEN_KEEPALIVE` rather than a struct of function pointers, so it
/// needs its own parser. The reason for generating it is the same one, though:
/// a hand-written backend drifts from the header it was written against, and
/// only one of the two backends being generated is an asymmetry with no
/// justification behind it.
library;

/// One exported function.
final class WasmFunction {
  const WasmFunction(this.name, this.returns, this.parameters);

  /// Its C name. Emscripten prefixes an underscore when exporting.
  final String name;

  /// The Dart interop type it returns.
  final String returns;

  /// Its parameters, in order, as (interop type, name).
  final List<(String, String)> parameters;

  /// What the module exposes it as.
  String get exported => '_$name';

  /// Lower camel case, which is what Dart wants.
  String get dartName => name[0].toLowerCase() + name.substring(1);
}

/// The interop type for a C type.
///
/// Everything crossing this boundary is a number except `bool`: `size_t`, every
/// pointer and every opaque handle are all indices into one linear heap, which
/// is what makes the mapping this small.
String _interopType(String c) {
  final bare = c.replaceAll('const', '').replaceAll('*', '').trim();
  if (bare == 'bool') return 'JSBoolean';
  if (bare == 'void' && !c.contains('*')) return 'void';
  return 'JSNumber';
}

final _comments = RegExp(r'/\*.*?\*/', dotAll: true);
final _lineComments = RegExp(r'//[^\n]*');
final _signature = RegExp(
  r'([A-Za-z_][\w \*]*?)\s*EMSCRIPTEN_KEEPALIVE\s+(\w+)\s*\(([^;]*?)\)\s*;',
  dotAll: true,
);

/// Every function [header] exports, in declaration order.
List<WasmFunction> parseWasmApi(String header) {
  final source = header.replaceAll(_comments, '').replaceAll(_lineComments, '');

  final functions = <WasmFunction>[];
  for (final match in _signature.allMatches(source)) {
    final returns = _interopType(match.group(1)!);
    final name = match.group(2)!;
    final parameters = <(String, String)>[];

    for (final raw in match.group(3)!.split(',')) {
      // Default arguments are C++ and say nothing about the call.
      final argument =
          raw.split('=').first.split(RegExp(r'\s+')).join(' ').trim();
      if (argument.isEmpty || argument == 'void') continue;

      final identifier = RegExp(r'(\w+)$').firstMatch(argument);
      if (identifier == null) continue;
      final parameterName = identifier.group(1)!;
      final type = argument.substring(0, identifier.start).trim();
      parameters.add((_interopType(type), _dartArgument(parameterName)));
    }
    functions.add(WasmFunction(name, returns, parameters));
  }
  return functions;
}

String _dartArgument(String name) {
  final parts = name.split('_');
  return parts.first +
      parts
          .skip(1)
          .map((p) => p.isEmpty ? '' : p[0].toUpperCase() + p.substring(1))
          .join();
}

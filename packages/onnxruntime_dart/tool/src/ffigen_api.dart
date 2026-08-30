/// Reads the `OrtApi` function-pointer signatures out of the ffigen bindings.
///
/// The header says what a parameter means; ffigen says how wide it is. Two C
/// enums with the same shape can land on `Int` and `UnsignedInt` depending on
/// their values, so re-deriving widths from the header only produces a second
/// opinion that can disagree with the struct the calls actually go through.
library;

import 'dart:io';

/// The FFI parameter types of one `OrtApi` member, in order.
typedef Signature = List<String>;

/// Parses every API struct in [file]: struct name to member name to signature.
Map<String, Map<String, Signature>> readApiSignatures(File file) {
  final source = file.readAsStringSync();
  final apis = <String, Map<String, Signature>>{};

  for (final struct in RegExp(r'final class (Ort\w+) extends ffi\.Struct \{')
      .allMatches(source)) {
    final end = source.indexOf('\n}', struct.end);
    final body = source.substring(struct.end, end < 0 ? source.length : end);

    final signatures = <String, Signature>{};
    for (final field in RegExp(
      r'external\s+(.*?)\s+(\w+);',
      dotAll: true,
    ).allMatches(body)) {
      final parameters = _parameters(field.group(1)!);
      if (parameters != null) signatures[field.group(2)!] = parameters;
    }
    if (signatures.isNotEmpty) apis[struct.group(1)!] = signatures;
  }

  if (!apis.containsKey('OrtApi')) {
    throw StateError('no OrtApi in ${file.path}');
  }
  return apis;
}

/// The parameter types of `Pointer<NativeFunction<R Function(...)>>`, or null
/// when [type] is not a function pointer.
Signature? _parameters(String type) {
  final open = type.indexOf('Function(');
  if (open < 0) return null;
  final arguments = _balanced(type, open + 'Function('.length - 1);
  if (arguments == null) return null;

  return [
    for (final parameter in _split(arguments))
      _normalise(parameter.replaceFirst(RegExp(r'\s+\w+$'), '')),
  ];
}

/// The text inside the parentheses starting at [open].
String? _balanced(String text, int open) {
  var depth = 0;
  for (var i = open; i < text.length; i++) {
    switch (text[i]) {
      case '(':
        depth++;
      case ')':
        if (--depth == 0) return text.substring(open + 1, i);
    }
  }
  return null;
}

/// Splits on commas that are not inside generics.
List<String> _split(String arguments) {
  final parts = <String>[];
  var depth = 0;
  var start = 0;
  for (var i = 0; i < arguments.length; i++) {
    switch (arguments[i]) {
      case '<' || '(':
        depth++;
      case '>' || ')':
        depth--;
      case ',' when depth == 0:
        parts.add(arguments.substring(start, i));
        start = i + 1;
    }
  }
  parts.add(arguments.substring(start));
  return [
    for (final part in parts)
      if (part.trim().isNotEmpty) part,
  ];
}

/// Drops the `ffi.` prefix and spells `OrtStatusPtr` as what it is.
String _normalise(String type) => type
    .replaceAll(RegExp(r'\s+'), '')
    .replaceAll('ffi.', '')
    .replaceAll('OrtStatusPtr', 'Pointer<OrtStatus>');

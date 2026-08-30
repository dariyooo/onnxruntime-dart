/// Parses the ONNX Runtime C API header.
///
/// The header is regular enough to read directly: every call is an
/// `ORT_API2_STATUS(Name, params)` inside an API struct, and the SAL annotation
/// on each parameter says which direction it goes. That is enough to derive a
/// Dart signature without guessing.
///
/// Which struct a declaration sits in matters: `OrtApi` is the main table, but
/// `OrtModelEditorApi`, `OrtCompileApi` and their siblings are separate tables
/// reached through their own getters, and a name only resolves against the one
/// that declares it.
library;

/// Which way a parameter goes, from its SAL annotation.
enum Direction {
  /// `_In_`, `_In_opt_`, `_In_reads_`. Becomes a Dart parameter.
  input,

  /// `_Out_`, `_Outptr_`. Becomes part of the return value.
  output,

  /// `_Inout_`. Passed in and modified, so it stays a parameter.
  inout,
}

/// One parameter of a C function.
final class CParameter {
  CParameter({
    required this.name,
    required this.type,
    required this.direction,
    this.arrayLengthParameter,
    this.isOptional = false,
  });

  final String name;

  /// The C type, with SAL annotations stripped.
  final String type;

  final Direction direction;

  /// For `_In_reads_(n)`, the parameter naming the length.
  final String? arrayLengthParameter;

  /// `_In_opt_`, so null is allowed.
  final bool isOptional;

  bool get isPointer => type.endsWith('*');

  @override
  String toString() => '${direction.name} $type $name'
      '${arrayLengthParameter == null ? '' : ' [len: $arrayLengthParameter]'}';
}

/// One `ORT_API2_STATUS` entry.
final class CFunction {
  CFunction({
    required this.name,
    required this.parameters,
    this.returnsStatus = true,
  });

  final String name;
  final List<CParameter> parameters;

  /// Whether the call returns an `OrtStatus` that has to be checked and
  /// released. Release functions return void and cannot fail.
  final bool returnsStatus;

  Iterable<CParameter> get inputs =>
      parameters.where((p) => p.direction != Direction.output);

  Iterable<CParameter> get outputs =>
      parameters.where((p) => p.direction == Direction.output);

  @override
  String toString() => '$name(${parameters.join(', ')})';
}

/// Reads every API struct in [header], keyed by struct name.
///
/// Both declaration forms are collected: `ORT_API2_STATUS`, which returns a
/// status, and `ORT_CLASS_RELEASE(X)`, which declares
/// `void ReleaseX(OrtX*)` and cannot fail.
Map<String, List<CFunction>> parseApis(String header) {
  final structs = _structSpans(header);
  final apis = <String, List<CFunction>>{};

  void add(int offset, CFunction function) {
    final struct = _structAt(structs, offset);
    if (struct != null) (apis[struct] ??= []).add(function);
  }

  for (final match in RegExp(
    r'ORT_API2_STATUS\(\s*(\w+)\s*,([^;]*)\)\s*;',
    multiLine: true,
  ).allMatches(header)) {
    final parameters = _parseParameters(match.group(2)!);
    if (parameters == null) continue;
    add(match.start, CFunction(name: match.group(1)!, parameters: parameters));
  }

  for (final match
      in RegExp(r'ORT_CLASS_RELEASE\((\w+)\)\s*;').allMatches(header)) {
    add(
      match.start,
      CFunction(
        name: 'Release${match.group(1)}',
        returnsStatus: false,
        parameters: [
          CParameter(
            name: 'input',
            type: 'Ort${match.group(1)}*',
            direction: Direction.input,
          ),
        ],
      ),
    );
  }

  return apis;
}

/// The half-open span of each `struct OrtXxx { ... }`, by brace depth.
Map<String, (int, int)> _structSpans(String header) {
  final spans = <String, (int, int)>{};
  for (final match
      in RegExp(r'\bstruct\s+(Ort\w*Api\w*)\s*\{').allMatches(header)) {
    final open = header.indexOf('{', match.start);
    var depth = 0;
    for (var i = open; i < header.length; i++) {
      if (header[i] == '{') depth++;
      if (header[i] == '}' && --depth == 0) {
        spans[match.group(1)!] = (open, i);
        break;
      }
    }
  }
  return spans;
}

/// The innermost struct containing [offset].
String? _structAt(Map<String, (int, int)> spans, int offset) {
  String? best;
  var width = -1;
  for (final entry in spans.entries) {
    final (start, end) = entry.value;
    if (offset < start || offset > end) continue;
    if (width < 0 || end - start < width) {
      best = entry.key;
      width = end - start;
    }
  }
  return best;
}

/// Splits a parameter list on commas outside parentheses.
///
/// `_Out_writes_bytes_(a, b)` contains a comma, so depth has to be tracked
/// rather than splitting naively.
List<String> _splitParameters(String text) {
  final parts = <String>[];
  final buffer = StringBuffer();
  var depth = 0;
  for (final rune in text.runes) {
    final char = String.fromCharCode(rune);
    if (char == '(') depth++;
    if (char == ')') depth--;
    if (char == ',' && depth == 0) {
      parts.add(buffer.toString());
      buffer.clear();
      continue;
    }
    buffer.write(char);
  }
  if (buffer.isNotEmpty) parts.add(buffer.toString());
  return parts.map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
}

List<CParameter>? _parseParameters(String text) {
  if (text.contains('...')) return null;

  final parameters = <CParameter>[];
  for (final raw in _splitParameters(text)) {
    final parameter = _parseParameter(raw);
    if (parameter == null) return null;
    parameters.add(parameter);
  }
  return parameters;
}

final _sal = RegExp(r'_(In|Out|Inout|Outptr)\w*_(?:\(([^)]*)\))?');

CParameter? _parseParameter(String raw) {
  var text = raw.replaceAll('\n', ' ').trim();
  if (text.isEmpty || text == 'void') return null;

  var direction = Direction.input;
  String? arrayLength;
  var optional = false;

  for (final match in _sal.allMatches(text)) {
    final annotation = match.group(0)!;
    if (annotation.startsWith('_Outptr') || annotation.startsWith('_Out')) {
      direction = Direction.output;
    } else if (annotation.startsWith('_Inout')) {
      direction = Direction.inout;
    }
    if (annotation.contains('_opt_')) optional = true;
    if (annotation.startsWith('_In_reads') && match.group(2) != null) {
      arrayLength = match.group(2)!.trim();
    }
  }
  text = text.replaceAll(_sal, ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

  // The name is the trailing identifier; the rest is the type.
  final name = RegExp(r'(\w+)\s*$').firstMatch(text)?.group(1);
  if (name == null) return null;
  final type = text.substring(0, text.length - name.length).trim();
  if (type.isEmpty) return null;

  return CParameter(
    name: name,
    type: type,
    direction: direction,
    arrayLengthParameter: arrayLength,
    isOptional: optional,
  );
}

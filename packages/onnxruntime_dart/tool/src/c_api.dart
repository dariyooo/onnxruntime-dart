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
    this.isEnum = false,
    this.isCalleeAllocated = false,
    this.isFunctionPointer = false,
  });

  final String name;

  /// The C type, with SAL annotations stripped.
  final String type;

  final Direction direction;

  /// For `_In_reads_(n)`, the parameter naming the length.
  final String? arrayLengthParameter;

  /// `_In_opt_`, so null is allowed.
  final bool isOptional;

  /// Whether [type] names a C enum, which crosses as its underlying integer.
  final bool isEnum;

  /// Whether [type] names a function-pointer typedef, which crosses as the
  /// `Pointer<NativeFunction<...>>` ffigen declared for it. Building one, and
  /// keeping it alive as long as the runtime holds it, is the caller's.
  final bool isFunctionPointer;

  /// `_Outptr_` rather than `_Out_`: the call allocates and hands back a
  /// pointer, instead of filling a buffer the caller allocated.
  ///
  /// The difference decides how much to allocate. A caller-allocated array
  /// needs room for every element up front, a callee-allocated one needs a
  /// single pointer cell and is read by walking what comes back.
  final bool isCalleeAllocated;

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
/// Three declaration forms are collected: `ORT_API2_STATUS`, which returns a
/// status; `ORT_CLASS_RELEASE(X)`, which declares `void ReleaseX(OrtX*)`; and
/// plain `void(ORT_API_CALL* Name)(params)` members, which are how the header
/// spells a call that cannot fail but still takes parameters.
Map<String, List<CFunction>> parseApis(String header) {
  final structs = _structSpans(header);
  final enums = parseEnums(header);
  final callbacks = parseFunctionPointers(header);
  final apis = <String, List<CFunction>>{};

  void add(int offset, CFunction function) {
    final struct = _structAt(structs, offset);
    if (struct != null) (apis[struct] ??= []).add(function);
  }

  for (final match in RegExp(
    r'ORT_API2_STATUS\(\s*(\w+)\s*,([^;]*)\)\s*;',
    multiLine: true,
  ).allMatches(header)) {
    final parameters = _parseParameters(match.group(2)!, enums, callbacks);
    if (parameters == null) continue;
    add(match.start, CFunction(name: match.group(1)!, parameters: parameters));
  }

  for (final match in RegExp(
    r'void\s*\(\s*ORT_API_CALL\s*\*\s*(\w+)\s*\)\s*\(([^;]*?)\)'
    r'(?:\s*NO_EXCEPTION)?(?:\s*ORT_ALL_ARGS_NONNULL)?\s*;',
    multiLine: true,
  ).allMatches(header)) {
    final parameters = _parseParameters(match.group(2)!, enums, callbacks);
    if (parameters == null) continue;
    add(
      match.start,
      CFunction(
        name: match.group(1)!,
        parameters: parameters,
        returnsStatus: false,
      ),
    );
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

/// The names of every `typedef enum { ... } Name;` in [header].
///
/// Read rather than listed: an enum added by a new ORT version would otherwise
/// silently drop every function that takes one.
/// Names of the function-pointer typedefs the header declares.
///
/// `typedef void(ORT_API_CALL* OrtLoggingFunction)(...)` and the plainer
/// `typedef void (*RunAsyncCallbackFn)(...)`, which the header uses for the
/// callbacks it does not route through the calling convention macro. Without
/// this a callback parameter looks like an unknown struct and the whole
/// function is skipped.
Set<String> parseFunctionPointers(String header) => {
      for (final match in RegExp(
        r'typedef\s+[\w\s*]+\(\s*(?:ORT_API_CALL\s*)?\*\s*(\w+)\s*\)\s*\(',
      ).allMatches(header))
        match.group(1)!,
    };

Set<String> parseEnums(String header) => {
      // Two spellings, and the header uses both. Most enums are typedef'd,
      // `typedef enum { ... } OrtErrorCode;`, but a few are declared bare:
      // `enum OrtSparseIndicesFormat { ... };`. Reading only the first kind
      // leaves every parameter of the second looking like an unknown type.
      for (final match in RegExp(
        r'typedef\s+enum\s*\w*\s*\{[^}]*\}\s*(\w+)\s*;',
        dotAll: true,
      ).allMatches(header))
        match.group(1)!,
      for (final match in RegExp(
        r'(?<!typedef\s)\benum\s+(\w+)\s*\{[^}]*\}\s*;',
        dotAll: true,
      ).allMatches(header))
        match.group(1)!,
    };

List<CParameter>? _parseParameters(
  String text,
  Set<String> enums,
  Set<String> callbacks,
) {
  if (text.contains('...')) return null;

  final parameters = <CParameter>[];
  for (final raw in _splitParameters(text)) {
    final parameter = _parseParameter(raw, enums, callbacks);
    if (parameter == null) return null;
    parameters.add(parameter);
  }
  return _withArrayLengths(parameters);
}

/// Suffixes naming the length of another parameter.
const _lengthSuffixes = ['_length', '_len', '_count'];

/// Pairs an out-pointer with its length parameter.
///
/// `GetDimensions(info, _Out_ int64_t* dim_values, size_t dim_values_length)`
/// predates `_Out_writes_`, so the annotation does not say it writes an array.
/// The naming does, and reading it as a single value would return one dimension
/// of a shape.
List<CParameter> _withArrayLengths(List<CParameter> parameters) {
  final names = {for (final p in parameters) p.name};
  final result = <CParameter>[];
  for (final (index, parameter) in parameters.indexed) {
    final length = parameter.direction == Direction.output &&
            parameter.arrayLengthParameter == null
        ? _lengthOf(parameter.name, names) ??
            _countAfter(parameter, parameters, index)
        : null;
    result.add(
      length == null
          ? parameter
          : CParameter(
              name: parameter.name,
              type: parameter.type,
              direction: parameter.direction,
              arrayLengthParameter: length,
              isOptional: parameter.isOptional,
              // Rebuilding drops whatever is not restated. `isEnum` was
              // being lost here, which turned an enum out-parameter paired
              // with a length back into a plain integer.
              isEnum: parameter.isEnum,
              isCalleeAllocated: parameter.isCalleeAllocated,
              isFunctionPointer: parameter.isFunctionPointer,
            ),
    );
  }
  return result;
}

/// The count parameter sitting immediately after a callee-allocated array.
///
/// `GetEpDevices(env, _Outptr_ ... ** ep_devices, _Out_ size_t* num_ep_devices)`
/// names its count `num_ep_devices`, which no suffix rule finds. Position is
/// what identifies it: the header writes the array and its length adjacently,
/// in that order, everywhere this shape appears.
String? _countAfter(
  CParameter parameter,
  List<CParameter> parameters,
  int index,
) {
  if (!parameter.isCalleeAllocated) return null;
  if (index + 1 >= parameters.length) return null;
  final next = parameters[index + 1];
  if (next.direction != Direction.output) return null;
  return const {'size_t*', 'int64_t*'}.contains(next.type) ? next.name : null;
}

String? _lengthOf(String name, Set<String> names) {
  for (final suffix in _lengthSuffixes) {
    if (names.contains('$name$suffix')) return '$name$suffix';
  }
  return null;
}

/// `_Frees_ptr_opt_` marks a release parameter, which goes in like any other.
final _sal = RegExp(r'_(In|Out|Inout|Outptr|Frees_ptr)\w*_(?:\(([^)]*)\))?');

CParameter? _parseParameter(
  String raw,
  Set<String> enums,
  Set<String> callbacks,
) {
  var text = raw.replaceAll('\n', ' ').trim();
  if (text.isEmpty || text == 'void') return null;

  var direction = Direction.input;
  String? arrayLength;
  var optional = false;
  var calleeAllocated = false;

  for (final match in _sal.allMatches(text)) {
    final annotation = match.group(0)!;
    if (annotation.startsWith('_Outptr') || annotation.startsWith('_Out')) {
      direction = Direction.output;
      if (annotation.startsWith('_Outptr')) calleeAllocated = true;
    } else if (annotation.startsWith('_Inout')) {
      direction = Direction.inout;
    }
    if (annotation.contains('_opt_')) optional = true;
    if ((annotation.startsWith('_In_reads') ||
            annotation.startsWith('_Out_writes')) &&
        match.group(2) != null) {
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
    isCalleeAllocated: calleeAllocated,
    isFunctionPointer: callbacks.contains(type),
    isEnum: enums.contains(
      type.replaceAll(RegExp(r'^(?:const\s+)?(?:enum\s+)?|\s*\*$'), '').trim(),
    ),
  );
}
